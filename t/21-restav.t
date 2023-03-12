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

{
	let ($dog, @notdogs) = %source;
	# Note that the order of @notdogs is as variable is values(%source).

	is_deeply([sort @notdogs], [ qw/meow oink squeak squwak/ ], "Extracted remaining values");
}

done_testing;
