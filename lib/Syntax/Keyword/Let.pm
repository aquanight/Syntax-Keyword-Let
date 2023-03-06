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
