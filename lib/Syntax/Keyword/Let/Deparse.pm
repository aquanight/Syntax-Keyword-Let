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
	OP_PADHV => opnumber('padhv'),
	OP_CONST => opnumber('const'),
};

use Devel::Peek;

sub B::Deparse::pp_destructure {
	my $self = shift;
	my ($op) = @_;
	my @kids;
	for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
		push @kids, $kid;
	}
	my $srcop = pop @kids;
	my @keyops;
	my @padops;
	(shift @kids)->type == OP_PUSHMARK or return "???";
	my ($ix) = grep { ($kids[$_]->type == OP_PUSHMARK) || ($kids[$_]->type == OP_PADRANGE) } keys @kids;
	defined $ix or return "???";
	@keyops = @kids[0 .. ($ix - 1)];
	@padops = @kids[($ix + 1) .. $#kids];
	my @keyset;
	for my $ix (0 .. $#padops) {
		my $dprs;
		$padops[$ix]->type == OP_PADSV || $padops[$ix]->type == OP_PADHV or die "WTF";
		my $varname = $self->padname($padops[$ix]->targ);
		if ($varname =~ m/^%/) {
			$ix > $#keyops or return "???";
			$dprs = $varname;
		}
		elsif (($keyops[$ix]->type == OP_CONST) && ($keyops[$ix]->private & B::OPpCONST_BARE)) {
			my $sv = $self->const_sv($keyops[$ix]);
			my $val = $sv->object_2svref->$*;
			if ($val eq substr($varname, 1)) {
				$dprs = $varname;
			}
			else {
				$dprs = sprintf "%s => %s", $val, $varname;
			}
		}
		else {
			$dprs = sprintf "{ %s } => %s", $self->deparse($keyops[$ix]), $varname;
		}
		push @keyset, $dprs;
	}
	return sprintf "let (%s) = %s", join(",", @keyset), $self->deparse($srcop);
}
