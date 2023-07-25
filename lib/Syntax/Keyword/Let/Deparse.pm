use v5.34;
use warnings;
package Syntax::Keyword::Let::Deparse;

our $VERSION = '0.01';

use B 'opnumber';

require B::Deparse;

use constant {
	OP_CUSTOM => opnumber('custom'),
	OP_PUSHMARK => opnumber('pushmark'),
	OP_PADRANGE => opnumber('padrange'),
	OP_PADSV => opnumber('padsv'),
	OP_PADAV => opnumber('padav'),
	OP_PADHV => opnumber('padhv'),
	OP_CONST => opnumber('const'),
	OP_NULL => opnumber('null'),
	OP_UNDEF => opnumber('undef'),
	OP_LIST => opnumber('list'),
	OPpRESTHV => 0x01,
	OPpRESTAV => 0x02,
	OPpNESTEDHV => 0x4,
	OPpNESTEDAV => 0x8,
};

BEGIN {
	require feature;
	if (exists $feature::feature{declared_refs}) {
		constant->import({
			OP_REFGEN => opnumber('refgen'),
			OP_SREFGEN => opnumber('srefgen'),
			OP_LVREF => opnumber('lvref'),
		});
	}
	else {
		# declared_refs not supported on this perl version, do not attempt to deparse aliased variables
		constant->import({
			OP_REFGEN => 0.1, # These values should never be numerically equal to any opcode produced by perl
			OP_SREFGEN => 0.1,
			OP_LVREF => 0.1,
		})
	}
}

use Devel::Peek;

# Not using lexical sub syntax with these because with scalars we can use $self->$parse_target(...)

my $parse_target = sub {
	my $self = shift;
	my ($target) = @_;
	if ($target->type == OP_PADSV || $target->type == OP_PADAV || $target->type == OP_PADHV) {
		# Simple scalar
		my $varname = $self->padname($target->targ);
		return ($varname, substr($varname, 1));
	}
	elsif ($target->type == OP_NULL && $target->targ == OP_SREFGEN) {
		# nulled out srefgen leading to an optimized LVREF
		$target = $target->first()//die "WTF";
		# This should be a nulled out OP_LIST
		$target->type == OP_NULL && $target->targ == OP_LIST or die "WTF";
		$target = $target->first()//die "WTF";
		# This should be LVREF
		$target->type == OP_LVREF or die "WTF";
		my $varname = $self->padname($target->targ);
		return ("\\$varname", substr($varname, 1));
	}
	elsif ($target->type == OP_UNDEF) {
		return ("undef", undef);
	}
	elsif ($target->type == OP_CUSTOM) {
		return ($self->deparse($target), undef);
	}
};

my $parse_hash_target_list = sub {
	my $self = shift;
	my ($op, @kids) = @_;
	my @parsed;
	my $restxvop;
	my $p = $op->private;
	if ($p & (OPpRESTHV | OPpRESTAV)) {
		$restxvop = pop @kids;
	}
	else {
		$restxvop = undef;
	}
	while (@kids) {
		my $keyop = shift(@kids);
		my $padop = shift(@kids);
		my ($target, $autoname) = $self->$parse_target($padop);
		my $str;
		if ($keyop->type == OP_CONST and $keyop->private & B::OPpCONST_BARE) {
			my $sv = $self->const_sv($keyop);
			my $val = $sv->object_2svref->$*;
			if (defined($autoname) && $val eq $autoname) {
				$str = $target;
			}
			else {
				$str = sprintf "%s => %s", $val, $target;
			}
		}
		else {
			$str = sprintf "{ %s } => %s", $self->deparse($keyop), $target;
		}
		push @parsed, $str;
	}
	defined($restxvop) and push @parsed, $self->$parse_target($restxvop);
	@parsed;
};

sub pp_nestedlet_real {
	my $self = shift;
	my ($op) = @_;
	my @kids;
	for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
		push @kids, $kid;
	}
	(shift @kids)->type == OP_PUSHMARK or return "???";
	my $p = $op->private;
	if ($p | OPpNESTEDHV) {
		my @items = $self->$parse_hash_target_list($op, @kids);
		return sprintf("{%s}", join(", ", @items));
	}
	elsif ($p | OPpNESTEDAV) {
		my @items;
		for my $k (@kids) {
			my ($target, undef) = $self->$parse_target($k);
			push @items, $target;
		}
		return sprintf("[%s]", join(", ", @items));
	}
}

sub pp_destructure_real {
	my $self = shift;
	my ($op) = @_;
	my @kids;
	for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
		push @kids, $kid;
	}
	my $srcop = pop @kids;
	my $targets;
	(shift @kids)->type == OP_PUSHMARK or return "???";
	if ($op->flags & B::OPf_SPECIAL) {
		@kids == 1 or die "WTF";
		$targets = $self->deparse($kids[0]);
	}
	else {
		
		my @dp = $self->$parse_hash_target_list($op, @kids);
		$targets = sprintf("(%s)", join(", ", @dp));
	}
	return sprintf("let %s = %s", $targets, $self->deparse($srcop));
}

no warnings 'redefine';
*B::Deparse::pp_destructure = \&pp_destructure_real;
*B::Deparse::pp_nestedlet = \&pp_nestedlet_real;

1;