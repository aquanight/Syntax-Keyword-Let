#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "XSParseKeyword.h"

static int build_let(pTHX_ OP** out, XSParseKeywordPiece* args[], size_t nargs, void* hookdata)
{
	size_t argix = 0;
	int varct = args[argix++]->i;
	OP* keyops = newLISTOP(OP_LIST, 0, (OP*)0, (OP*)0);
	OP* varops = newLISTOP(OP_LIST, 0, (OP*)0, (OP*)0);
	while (varct-- > 0)
	{
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
				case 1: /* XPK_BRACEKSCOPE { XPK_TERMEXPR } */
				key_op = args[argix++]->op;
				break;
			}
		}
		else key_op = (OP*)0;
		int padix = args[argix++]->i;
		OP* varop = newOP(OP_PADSV, (OPpLVAL_INTRO<<8)|OPf_MOD|OPf_REF);
		varop->op_targ = padix;
		if (!key_op)
		{
			char* name = PadnamePV(PadnamelistARRAY(PL_comppad_name)[padix]); /* Note that this includes the leading '$' */
			SV* sv = newSVpv(name + 1, 0);
			SvREADONLY_on(sv);
			key_op = newSVOP(OP_CONST, 0, sv);
		}
		op_append_elem(OP_LIST, keyops, key_op);
		op_append_elem(OP_LIST, varops, varop);
	}
	OP* srcop = args[argix++]->op;
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
	OP* hsliceop = newLISTOP(OP_LIST, 0, (OP*)0, (OP*)0);
	hsliceop = op_append_elem(OP_LIST, hsliceop, keyops);
	hsliceop = op_append_elem(OP_LIST, hsliceop, srcop);
	hsliceop = op_convert_list(OP_HSLICE, 0, hsliceop);
	
	*out = newASSIGNOP(0, varops, 0, newLISTOP(OP_LIST, 0, hsliceop, (OP*)0));
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
			XPK_LEXVAR_MY(XPK_LEXVAR_SCALAR)
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

MODULE = Syntax::Keyword::Let  PACKAGE = Syntax::Keyword::Let

BOOT:
	boot_xs_parse_keyword(0);

	register_xs_parse_keyword("let", &kwhooks_let, (void*)0);

