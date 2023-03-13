use v5.34;
use warnings;
package Syntax::Keyword::Let;

our $VERSION = '0.01';

# ABSTRACT: let statement with hash destructuring

use XSLoader;

XSLoader::load(__PACKAGE__, $VERSION);

sub import {
	$^H{'Syntax::Keyword::Let'} = 1;
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

let declares the listed to be lexical to the enclosing block, file, or eval. The key/variable list must be placed inside parentheses, even if it's just a single variable.

KEYVARLIST is a comma-separated list of key and variable pairs enclosed in parentheses. The key can either be a bareword, or it can be an expression enclosed in braces ({}).
Note that you must use braces even if it's a quoted string constant. The key must be separated from the variable by using the "fat comma" (=>). All variables involved must be
scalar variables (starting with a $), since hash values are scalars.

You can leave out the key (and fat comma) entirely, giving just a variable name. If you do, the key is assumed to be the name of the variable (minus the leading $).

If the key doesn't exist in the source hash, the associated variable is assigned an undefined value.

Alternatively, your last variable can be a hash (no key may be specified): this hash will be populated with all the keys and values from the source that weren't put in
another variable.

HASHEXPR is an expression that provides the source hash from which values are assigned to the assorted variables. It could be a simple hash variable, a hash dereference, or
any other kind of expression that will return a list of name and value pairs.

In list context, the let operator returns the variables and hash elements that were just assigned to.

In scalar context, the let operator returns an integer value counting the number of keys in the source hash that existed and were assigned to a variable. Note that this
doesn't count variables that were assigned undefined because their value didn't exist.

=head1 LIMITATIONS

=item * You cannot use 'undef' to skip values. While you could just not ask for them, this also prevents you from excluding them from your %remain hash.

=item * Array destructuring isn't possible yet but you can use 'my' as normal.

=item * Deep or complex destructuring isn't yet supported.

=item * You presently can only destructure into new lexical variables. Reusing existing variables is not yet available. Note that this will constitute a breaking change if done.

=item * Refaliasing is not supported (binding aliases to the source hash elements)

=item * You cannot declare a variable and use it in the same expression (such as across an 'and' operator). This same limitation applies to 'my'.