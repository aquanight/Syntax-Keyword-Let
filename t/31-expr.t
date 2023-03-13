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
	notdef => undef,
);

my $scalar;
my @list;

if ((let ($dog) = %source)) {
	pass();
}
else {
	fail("Using let in expression with defined and existing value");
}

if (let ($notdef) = %source) {
	pass();
}
else {
	fail("Using let in expression with existing undef value");
}

if (let ($missing) = %source) {
	fail("Using let in expression with nonexistent value");
}
else {
	pass();
}


done_testing;
