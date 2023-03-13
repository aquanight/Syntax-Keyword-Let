#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "XSParseKeyword.h"

/*
Effect of op flags:

OPpRESTHV : Indicates that a 'rest item' - which is a hash - is on the stack to receive all remaining key/value pairs. Note that it will be with the rest of the target variables.

Context:
void context -> returns nothing, obviously
scalar context -> returns the number of *existing* keys extracted from the source hash
list context -> returns the variables assigned to

Note a key difference with scalar context compared to, say, list assignment. For example:

$count = (my ($dog) = $hash{dog}); # Always 1.
$count = (let ($dog) = %hash); # 1 if and only if exists $hash{dog} - otherwise 0.

If you want to also filter out values that exist but are undefined, use defined() operator:
let ($dog) = %hash; if (defined($dog)) { ... }
*/

/* Order of operators:
LISTOP DESTRUCTURE
	PUSHMARK
	key operators
	PUSHMARK
	target operators (PADSV, PADHV)
	source operator
*/

#define OPpRESTHV 0x01 /* indicates that an HV is present to receive leftover items */

#define DBG(...) warn(__VA_ARGS__)

static XOP xop_destructure;
static OP* pp_destructure(pTHX)
{
	/* Alright, UNOP_AUX has ticked me off enough. We're doing this AASSIGN style. */
	dSP;
	HV* const hv = MUTABLE_HV(POPs);
	HV* resthv = (PL_op->op_private & OPpRESTHV ? newHV() : NULL);
	
	int lastkeymark = POPMARK;
	int firstkeymark = POPMARK;
	SV** lasttargelem = SP;
	SV** lastkeyelem = PL_stack_base + lastkeymark;
	SV** firstkeyelem = PL_stack_base + firstkeymark + 1;
	SV** firsttargelem = lastkeyelem + 1;
	IV retcount = 0;
	int gimme = GIMME_V;
	
	/* resthv only needs to track the keys from the source hv */
	if (resthv)
	{
		HE *ent;
		for (hv_iterinit(hv); ent = hv_iternext(hv);)
		{
			I32 keylen;
			char* key = hv_iterkey(ent, &keylen);
			SV* store = newSV(0);
			if (!hv_store(resthv, key, keylen, store, 0))
				SvREFCNT_dec(store);
		}
	}
	
	SV** keyelem = firstkeyelem;
	SV** targelem = firsttargelem;
	
	while (LIKELY(targelem <= lasttargelem))
	{
		SV* lsv = *(targelem++);
		if (SvTYPE(lsv) == SVt_PVHV)
		{
			HV* lhv = MUTABLE_HV(lsv);
			/* We have encountered a 'rest' HV which should be the last such HV */
			assert(resthv);
			assert(targelem > lasttargelem);
			/* There should also be no keys left */
			assert(keyelem > lastkeyelem);
			SP = keyelem - 1;
			HE* ent;
			for (hv_iterinit(resthv); ent = hv_iternext(resthv);)
			{
				I32 keylen;
				char* key = hv_iterkey(ent, &keylen);
				SV** valsv = hv_fetch(hv, key, keylen, 0);
				if (gimme == G_ARRAY)
				{
					SV* keysv = hv_iterkeysv(ent);
					XPUSHs(keysv);
				}
				if (valsv && *valsv)
				{
					SV* store = newSVsv(*valsv);
					if (!hv_store(lhv, key, keylen, store, 0)) SvREFCNT_dec(store);
					++retcount;
					if (gimme == G_ARRAY)
					{
						XPUSHs(store);
					}
				}
				else if (gimme == G_ARRAY)
				{
					SV* store = newSV(0);
					if (!hv_store(lhv, key, keylen, store, 0)) sv_2mortal(store);
					XPUSHs(store);
				}
			}
			RETURN;
		}
		else
		{
			assert(SvTYPE(lsv) < SVt_PVAV);
			assert(keyelem <= lastkeyelem);
			const char* key;
			STRLEN klen;
			key = SvPV_const(*keyelem, klen);
			if (resthv)
			{
				hv_delete(resthv, key, klen, G_DISCARD);
			}
			SV** valsv = hv_fetch(hv, key, klen, 0);
			if (valsv && *valsv)
			{
				sv_setsv(lsv, *valsv);
				++retcount;
			}
			else
				sv_set_undef(lsv);
			*keyelem++ = lsv;
		}
	}
	
	if (gimme == G_VOID)
		SP = firstkeyelem - 1;
	else if (gimme == G_SCALAR)
	{
		SP = firstkeyelem;
		EXTEND(SP, 1);
		sv_setiv(*SP, retcount);
	}
	else //if (GIMME_V == G_ARRAY)
		SP = keyelem - 1;
	
	RETURN;
}

static int build_let(pTHX_ OP** out, XSParseKeywordPiece* args[], size_t nargs, void* hookdata)
{
	size_t argix = 0;
	OP* keyops = newLISTOP(OP_LIST, 0, NULL, NULL);
	OP* padops = newLISTOP(OP_LIST, 0, NULL, NULL);
	I32 op_private = 0;
	int varct = args[argix++]->i;
	
	while (varct-- > 0)
	{
		if (op_private & OPpRESTHV)
		{
			/* If we are even here, it's because we have another destructure element after a "rest" destructure.
			*/
			Perl_yyerror(aTHX_ "Expected end of destructure list");
			/* Note that we continue because unless this is an unrecoverable error, we need to still return some kind of optree */
			/* (yyerror can die() out sometimes but that's not our problem anymore) */
		}
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
		OP* padop;
		if (padsvtype == SVt_PVHV)
		{
			if (key_op)
			{
				Perl_yyerror(aTHX_ "Partial destructure to hash is not yet supported");
			}
			padop = newOP(OP_PADHV, OPf_REF|OPf_MOD|(OPpLVAL_INTRO << 8));
			padop->op_targ = padix;
			op_private |= OPpRESTHV;
		}
		else
		{
			assert(padsvtype < SVt_PVAV);
			if (!key_op)
			{
				char* name = PadnamePV(PadnamelistARRAY(PL_comppad_name)[padix]);
				SV* sv = newSVpv(name + 1, 0);
				SvREADONLY_on(sv);
				key_op = newSVOP(OP_CONST, 0, sv);
			}
			op_append_elem(OP_LIST, keyops, key_op);
			padop = newOP(OP_PADSV, OPf_REF|OPf_MOD|(OPpLVAL_INTRO << 8));
			padop->op_targ = padix;
		}
		op_append_elem(OP_LIST, padops, padop);
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
		}
		break;
	}
	OP* letop = op_append_list(OP_LIST, keyops, padops);
	letop = op_append_elem(OP_LIST, letop, srcop);
	//letop = op_convert_list(OP_CUSTOM, op_private << 8, letop);
	letop->op_type = OP_CUSTOM;
	letop->op_private = op_private;
	letop->op_ppaddr = pp_destructure;
	if (PL_op_mask && PL_op_mask[OP_CUSTOM])
	{
		op_free(letop);
		croak("destructure' trapped by operation mask");
	}
	else
		letop = PL_check[OP_CUSTOM](aTHX_ letop);
	*out = letop;
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
			XPK_LEXVAR_MY(XPK_LEXVAR_SCALAR | XPK_LEXVAR_HASH)
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

