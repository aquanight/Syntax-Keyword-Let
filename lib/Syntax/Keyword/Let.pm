use v5.34;
use warnings;
package Syntax::Keyword::Let;

our $VERSION = '0.02';

use Carp ();

# ABSTRACT: let statement with hash destructuring

use XSLoader;

XSLoader::load(__PACKAGE__, $VERSION);

sub import {
	my $pkg = shift;
	unless (@_) {
		@_ = ('let');
	}
	for my $arg (@_) {
		if ($arg eq 'let') {
			$^H{'Syntax::Keyword::Let'} = 1;
		}
		else { Carp::croak("Unrecognized symbol '$arg'"); }
	}
}

sub B::Deparse::pp_destructure {
	require Syntax::Keyword::Let::Deparse;
	goto &Syntax::Keyword::Let::Deparse::pp_destructure_real;
}

sub B::Deparse::pp_nestedlet {
	require Syntax::Keyword::Let::Deparse;
	goto &Syntax::Keyword::Let::Deparse::pp_nestedlet_real;
}

1;

=head1 NAME

Syntax::Keyword::Let - simplified hash extraction

=head1 SYNOPSIS

	use Syntax::Keyword::Let;
	
	my %source = ( ... );
	
	let ($key, other => $value, { $computed } => $result, %remainder) = %source;

=head1 DESCRIPTION

The hash destructuring assignment provides a simpler way to retrieve multiple values from a hash.

Of course, this could already be done with something like

	my ($key, $value, $result) = @source{'key', 'other', $computed};
	
But this has a few downsides:

=over 4

=item * 'key' had to be typed twice.

=item * The relation of hash keys and the variables receiving them can end up far apart, especially as the size of the assignment expression increases

=item * No ability to put the "leftovers" into a hash except by modifying the source hash (delete @source{...}).

=back

The 'let' keyword rearranges the flow of hash assignment so you can put keys right next to the variables they go into. You can also skip double-writing the keys
that end up being the same name as the variable they go into, thus reducing one possible source of errors.

=head1 USAGE

    let (KEYVARLIST) = HASHEXPR;

    let {KEYVARLIST} = EXPR;
    
    let [VARLIST] = EXPR;

let declares the listed variables to be lexical to the enclosing block, file, or C<eval>. The key/variable list must be placed inside parentheses, braces, or brackets, even if it's
just a single variable.

KEYVARLIST is a comma-separated list of key and variable pairs enclosed in parentheses or curly braces. The key can either be a bareword, or it can be an expression enclosed in braces ({}).
Note that you must use braces even if it's a quoted string constant. The key must be separated from the variable by using the "fat comma" (=>). All variables involved must be
scalar variables (starting with a $), since hash values are scalars.

VARLIST is a comma-separated list of variables, enclosed in square brackets. No key expressions are allowed here: array elements are simply extracted in order.

You can leave out the key (and fat comma) entirely, giving just a variable name. If you do, the key is assumed to be the name of the variable (minus the leading $).

If the key doesn't exist in the source hash, the associated variable is assigned an undefined value.

The last variable of KEYVARLIST may be either an array or hash. A hash will be populated with the keys and values not extracted to other variables. An array will be populated with key/value pairs.
The order of key/value pairs given to a trailing array is per the usual order of hash elements.

The last variable of a bracketed VARLIST can be an array, which will receive all remaining items in the array.

HASHEXPR is an expression that provides the source hash from which values are assigned to the assorted variables. It could be a simple hash variable, a hash dereference, or
any other kind of expression that will return a list of name and value pairs. HASHEXPR can only be used when KEYVARLIST is enclosed in parentheses.

EXPR is can be any expression. If you used curly braces around KEYVARLIST, it will be treated as a hash reference. If you used square brackets, it will be treated as an array reference.

The stability of results from a tied or magical source hash, especially when a trailing "remainder" hash is used should be considered "best effort".

The let operator returns an integer value counting the number of values that existed and were assigned to a variable. In particular, this count does not count variables assigned undef because
the source hash or array had no item for that variable. It also is distinct from the result produced by list assignment in scalar context - which normally is simply the number of items on the right
hand side.

=head1 EXAMPLES

	use Syntax::Keyword::Let;
	
	my %source = (
		cat => "meow",
		dog => "bark",
		pie => "round",
	);
	
	let ($cat) = %source; # $cat contains "meow"
	
	if (let ($dog) = %source) {
		say "Dog goes $dog";
	}
	
	if (let (missing => $var) = %source) {
		say 'This won't be reached: missing isn't in %source so let () returned 0';
	}
	
	let ($pie, %not_pie) = %source;
	
	exists $not_pie{pie} and say "This shouldn't be here";
	
	sub make_sounds {
		print "Noise: $_" for @_;
	}
	
	make_sounds(let ($cat, $dog) = %source);


=head1 LIMITATIONS

=over 4

=item * You cannot use 'undef' to skip values. While you could just not ask for them, this also prevents you from excluding them from your %remain hash.

=item * Array destructuring isn't possible yet but you can use 'my' as normal.

=item * Deep or complex destructuring isn't yet supported.

=item * You presently can only destructure into new lexical variables. Reusing existing variables is not yet available. Note that this will constitute a breaking change if done.

=item * Refaliasing is not supported (binding aliases to the source hash elements)

=item * You cannot declare a variable and use it in the same expression (such as across an 'and' operator). This same limitation applies to 'my'.

=back
