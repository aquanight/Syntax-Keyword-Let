#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Syntax::Keyword::Let;

my %source = (
	dog => "bark",
	cat => "meow",
	pig => "oink",
	rat => "squeak",
	bird => "squwak",
);

my $scalar;
my @list;

{
	$scalar = let ($dog, $cat) = %source;

	is($scalar, 2, "Scalar let returns the number keys retrieved");

	$scalar = let ($pig, $missing) = %source;

	is($scalar, 1, "Return count does not include items missing from the hash");
}

{
	@list = let ($dog, $cat) = %source;
	
	is_deeply(\@list, [ "bark", "meow" ], "List-context let returns the assignees");
}

done_testing;
