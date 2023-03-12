#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "XSParseKeyword.h"

/*
Okay hypothetically we can store a destructuring recipe inside UNOP_AUX_item
The (unoptimized) optree has to look something like this:
UNOP_AUX OP_DESTRUCTURE (AUX = recipe)
	LISTOP OP_LIST (can probably be nulled out)
		OP PUSHMARK
		<list of key expression ops>
		<last op is the root container>

So what is the recipe:
UNOP_AUX_item lets us put one of the following types (it's a union):
	PADOFFSET, SV*, IV, UV, char*, SSize_t

there's no "type" member so we have to be very strict about the sequence of operations

For this current version, we only destructure hashes and one layer, so the item set is very simple:
	let ($autokey, key => $namedkey, {EXPR} => $computedkey) = %hash;
	UNOP_AUX OP_DESTRUCTURE
		LISTOP OP_LIST
			OP OP_PUSHMARK
			possibly multiple: *OP EXPR
			OP PADHV %hash

The item set contains:
UV size -> size, in items, of the destructure recipe, including this item
UV action_flags -> flags for the destructuring about to occur
PADOFFSET padtgt -> pad index for a RESTHV or RESTAV target, 0 if no restav/resthv is used.
PADOFFSET[] padsv -> pad index of scalars to receive a value, the key comes from the stack.

*/

#define DSTRCTR_SRC_STACK 0x00 /* Take the source HV from the stack. Note that OPf_STACKED further signals that we can treat such PADHV as a temporary. */
//#define DSTRCTR_SRC_PADHV 0x01 /* Take PADOFFSET padsrc value and use it to grab a lexical HV */
//#define DSTRCTR_SRC_GVHV 0x02 /* Take an SV* padsrc value, it's actually a GV*, get the HV out of it and use that as source */
#define DSTRCTR_RESTHV 0x04 /* Take a PADOFFSET padtgt and set up HV* resthv */
#define DSTRCTR_RESTAV 0x08 /* Take a PADOFFSET padtgt and set up AV* restav */
#define DSTRCTR_NEEDREST (DSTRCTR_RESTHV|DSTRCTR_RESTAV)

/*
Effect of op flags:
OPf_WANT_VOID : No value returned
OPf_WANT_SCALAR : Return value is the number of EXISTING keys from the hash destructured.
OPf_WANT_LIST : Honestly don't have an actual clue what to return.
(Context will actually be determined by GIMME_V)
OPf_REF : If set, restav/resthv are put on the stack directly for further modification (let being used as an lvalue)
OPf_MOD : Currently this should only get set alongside OPf_REF so it doesn't do anything extra
OPf_STACKED : The HV put on the stack is a temporary (one we created from the keyword parse) - so we may instead delete and seize from the hash rather than having to copy.
	(We can also safely assume said hash is not magical.)
	Note: without this flag the HV is still coming from the stack but it's coming by way of PADHV or RV2HV from a nontemporary source (GV or a reference of unknown origin). In theory
	we'll eventually fold PADHV/RV2HV+GV sources into the UNOP_aux data somehow.

*/

/* Behavior regarding the input hash:
- When the source is a hash variable or hash dereference, we have to assume we don't own the hash, so we *must* copy the values from the hash.
	resthv, if needed, will be a new hash which will be populated by iterating the incoming hash. When we destructure into variables we will first delete from
	resthv if we can and reuse that value SV. If not we will try hv again (and copy from it), and if that fails then we will set undef.
- When the source is a list expression, we wrap it in an anonymous hash creation and dereference and apply the OPf_STACKED flag, which will trigger "temp hash"
	optimization. All destructures just *delete* from hv and reuse the value SV.
When RESTHV is found we can just drop resthv into place and then release our reference.
RESTAV is a bit more complicated.
*/

#define DBG(...) warn(__VA_ARGS__)

static XOP xop_destructure;
static OP* pp_destructure(pTHX)
{
	dSP; dMARK; dORIGMARK;
	UNOP_AUX_item* recipe = cUNOP_AUXx(PL_op)->op_aux;
	HV* const hv = MUTABLE_HV(POPs);
	HV* resthv = NULL;
	AV* restav = NULL;
	UV size = (recipe++)->uv;
	IV retcount = 0;
	IV restkeycount = 0;
	
	UV rec_flags = (recipe++)->uv;
	
	PADOFFSET restxvpad = (recipe++)->pad_offset;
	
	if (PL_op->op_flags & OPf_STACKED)
	{
		assert(!SvMAGICAL(hv));
		resthv = hv;
		restkeycount = HvUSEDKEYS(hv);
	}
	else if (rec_flags & DSTRCTR_NEEDREST)
	{
		resthv = newHV();
		sv_2mortal(MUTABLE_SV(resthv));
		HE *ent;
		for (hv_iterinit(hv); ent = hv_iternext(hv);)
		{
			I32 keylen;
			char* key = hv_iterkey(ent, &keylen);
			SV* store = newSVsv(hv_iterval(hv, ent));
			if (!hv_store(resthv, key, keylen, store, 0)) SvREFCNT_dec(store);
			else ++restkeycount;
		}
	}
	if (rec_flags & DSTRCTR_RESTHV)
	{
		SV** resthvpad = &PAD_SVl(restxvpad);
		SvREFCNT_dec_NN(*resthvpad);
		*resthvpad = SvREFCNT_inc_NN(MUTABLE_SV(resthv));
		SvTEMP_off(resthv);
		save_clearsv(resthvpad);
	}
	if (rec_flags & DSTRCTR_RESTAV)
	{
		SV** restavpad = &PAD_SVl(restxvpad);
		restav = (AV*)*restavpad;
		av_clear(restav);
		save_clearsv(restavpad);
	}
	
	while (++MARK <= SP)
	{
		SV* const keysv = *MARK;
		PADOFFSET targ = (recipe++)->pad_offset;
		SV** padtarg = &PAD_SVl(targ);
		SV* valsv = NULL;
		
		//DBG("> Scalar for key %" SVf, SVfARG(keysv));
		
		if (resthv)
		{
			valsv = hv_delete_ent(resthv, keysv, 0, 0);
			/* Reverse the mortal-izing effect of hv_delete_ent - we want to reuse this SV* */
			SvREFCNT_inc(valsv);
			SvTEMP_off(valsv);
		}
		if (!valsv)
		{
			//DBG(">> Not in resthv or no resthv in use");
			/* If it wasn't found in resthv, retry from hv in case a tied hash has lied about its key enumeration */
			HE* ent = hv_fetch_ent(hv, keysv, 0, 0);
			if (ent) valsv = newSVsv(HeVAL(ent));
		}
		if (valsv) ++retcount;
		else valsv = newSV(0);
		SvREFCNT_dec(*padtarg);
		*padtarg = valsv;
		save_clearsv(padtarg);
		*MARK = valsv;
	}
	
	if (restav)
	{
		HE* ent;
		for (hv_iterinit(resthv); ent = hv_iternext(resthv);)
		{
			SV* valsv = hv_iterval(resthv, ent);
			av_push(restav, newSVsv(valsv));
		}
	}
	
	if (restav || resthv) retcount += restkeycount;
	
	if (GIMME_V == G_ARRAY)
	{
		DBG("> Returning in list context");
		DBG("> There are %lu items already", (unsigned long)(SP - PL_stack_base));
		DBG("> We started with %lu items", (unsigned long)(PL_stack_sp - PL_stack_base));
		if (restav)
		{
			if (PL_op->op_flags & OPf_REF)
				XPUSHs(MUTABLE_SV(restav)); /* Push the AV directly per OPf_REF */
			else
			{
				/* Pour the AV out onto the stack */
				/* Sadly, S_pushav would be perfect for the job, but it's a static function, so we have to duplicate it */
				const SSize_t maxarg = AvFILL(restav) + 1;
				EXTEND(SP, maxarg);
				PADOFFSET i;
				for (i =  0; i < (PADOFFSET)maxarg; i++)
				{
					SV** const svp = av_fetch(restav, i, FALSE);
					SP[i+1] = LIKELY(svp) ? *svp : UNLIKELY(PL_op->op_flags & OPf_MOD) ? Perl_av_nonelem(aTHX_ restav, i) : &PL_sv_undef;
				}
				SP += maxarg;
				PUTBACK;
			}
		}
		if (resthv)
		{
			if (PL_op->op_flags & OPf_REF)
				XPUSHs(MUTABLE_SV(resthv));
			else
			{
				HE* ent;
				for (hv_iterinit(resthv); ent = hv_iternext(resthv);)
				{
					SV* keysv = hv_iterkeysv(ent);
					PUSHs(keysv);
					SV* valsv = hv_iterval(resthv, ent);
					PUSHs(valsv);
				}
			}
		}
		DBG("> There are again %lu items already", (unsigned long)(SP - PL_stack_base));
	}
	else
	{
		MARK = ORIGMARK;
		SP = MARK;
		if (GIMME_V == G_SCALAR)
		{
			mPUSHi(retcount);
		}
	}
	
	RETURN;
}


OP* newDSTRCTROP(pTHX_ U32 flags, OP* first, UNOP_AUX_item* recipe)
{
	OP* op = newUNOP_AUX(OP_CUSTOM, flags, first, recipe);
	op->op_ppaddr = &pp_destructure;
	op->op_private = (U8)(flags >> 8);
	return op;
}

static int build_let(pTHX_ OP** out, XSParseKeywordPiece* args[], size_t nargs, void* hookdata)
{
	size_t argix = 0;
	int varct = args[argix++]->i;
	UNOP_AUX_item* recipe = PerlMemShared_malloc(sizeof(UNOP_AUX_item) * (varct + 3));
	recipe[0].uv = varct + 3;
	recipe[1].uv = DSTRCTR_SRC_STACK;
	recipe[2].pad_offset = 0;
	int rcpsclrix = 3;
	OP* keyops = newLISTOP(OP_LIST, 0, (OP*)0, (OP*)0);
	I32 op_flags = 0;
	while (varct-- > 0)
	{
		if (recipe[1].uv & DSTRCTR_NEEDREST)
		{
			/* If we are even here, it's because we have another destructure element after a "rest" destructure.
			*/
			Perl_yyerror(aTHX_ "Expected end of destructure list");
			/* Note that we continue because unless this is an unrecoverable error, we need to still return some kind of optree */
		}
		bool seen_rest = FALSE;
		int has_name = args[argix++]->i;
		OP* key_op;
		if (has_name)
		{
			int which = args[argix++]->i;
			switch (which)
			{
				case 0: /* XPK_IDENT */
				{
					SV* sv_key = args[argix++]->sv;
					SvREADONLY_on(sv_key);
					key_op = newSVOP(OP_CONST, 0, sv_key);
				}
				break;
				case 1: /* XPK_BRACESCOPE ( XPK_TERMEXPR ) */
				key_op = op_contextualize(args[argix++]->op, G_SCALAR);
				break;
			}
		}
		else key_op = NULL;
		PADOFFSET padix = (PADOFFSET)(args[argix++]->i);
		SV* padsv = PAD_SVl(padix);
		const svtype padsvtype = SvTYPE(padsv);
		if (padsvtype == SVt_PVAV || padsvtype == SVt_PVHV)
		{
			if (key_op)
			{
				if (padsvtype == SVt_PVAV)
					Perl_yyerror(aTHX_ "Partial destructure to array is not yet supported");
				else
					Perl_yyerror(aTHX_ "Partial destructure to hash is not yet supported");
			}
			/* Setup RESTAV or RESTHV */
			recipe[1].uv |= padsvtype == SVt_PVAV ? DSTRCTR_RESTAV : DSTRCTR_RESTHV;
			recipe[2].pad_offset = padix;
		}
		else
		{
			if (padsvtype == SVt_PVCV) /* XPK shouldn't produce CVs from XPK_LEXVAR_MY but just in case... */
			{
				Perl_yyerror(aTHX_ "Illegal attempt to destructure into lexical sub");
			}
			if (!key_op)
			{
				char* name = PadnamePV(PadnamelistARRAY(PL_comppad_name)[padix]);
				SV* sv = newSVpv(name + 1, 0);
				SvREADONLY_on(sv);
				key_op = newSVOP(OP_CONST, 0, sv);
			}
			op_append_elem(OP_LIST, keyops, key_op);
			recipe[rcpsclrix++].pad_offset = padix;
		}
	}
	OP* srcop = op_contextualize(args[argix++]->op, G_ARRAY);
	switch (srcop->op_type)
	{
		case OP_PADHV:
		case OP_RV2HV:
			srcop->op_flags |= OPf_REF;
			break;
		default:
		{
			/* Wrap an arbitrary list into a hash construct and dereference */
			OP* hashop = newLISTOP(OP_LIST, 0, (OP*)0, (OP*)0);
			hashop = op_append_elem(OP_LIST, hashop, srcop);
			hashop = op_convert_list(OP_ANONHASH, 0, hashop);
			srcop = newUNOP(OP_RV2HV, OPf_REF, hashop);
			op_flags |= OPf_STACKED;
		}
		break;
	}
	op_append_elem(OP_LIST, keyops, srcop);
	keyops = op_convert_list(OP_LIST, 0, keyops);
	keyops = op_contextualize(keyops, G_ARRAY);
	OP* o = newDSTRCTROP(aTHX_ op_flags, keyops, recipe);
	*out = o;
	return KEYWORD_PLUGIN_EXPR;
}

static const struct XSParseKeywordPieceType pieces_let[] = {
	XPK_PARENSCOPE(
		XPK_COMMALIST(
			XPK_OPTIONAL(
				XPK_CHOICE(
					XPK_IDENT,
					XPK_BRACESCOPE(XPK_TERMEXPR_SCALARCTX)
				),
				XPK_LITERAL("=>")
			),
			XPK_LEXVAR_MY(XPK_LEXVAR_ANY)
		)
	),
	XPK_EQUALS,
	XPK_TERMEXPR
};

static const struct XSParseKeywordHooks kwhooks_let = {
	.permit_hintkey = "Syntax::Keyword::Let",
	.pieces = pieces_let,
	.build = build_let,
};

static Perl_ophook_t _old_opfree;

static void _free_destructure(pTHX_ OP* o)
{
	if (o->op_type == OP_CUSTOM && o->op_ppaddr == pp_destructure)
	{
		UNOP_AUX_item* recipe = cUNOP_AUXx(o)->op_aux;
		PerlMemShared_free(recipe);
		cUNOP_AUXx(o)->op_aux = NULL;
	}
	else
		_old_opfree(aTHX_ o);
}

MODULE = Syntax::Keyword::Let  PACKAGE = Syntax::Keyword::Let

BOOT:
	boot_xs_parse_keyword(0);
	
	XopENTRY_set(&xop_destructure, xop_name, "destructure");
	XopENTRY_set(&xop_destructure, xop_desc, "deconstruct hash");
	XopENTRY_set(&xop_destructure, xop_class, OA_UNOP_AUX);
	Perl_custom_op_register(aTHX_ &pp_destructure, &xop_destructure);

	register_xs_parse_keyword("let", &kwhooks_let, (void*)0);

