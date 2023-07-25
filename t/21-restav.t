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

	my %notdogs = @notdogs;

	is_deeply([sort keys %notdogs], [qw/bird cat pig rat/], "Extracted all other keys");

	is_deeply(\%notdogs, { %source{qw/bird cat pig rat/} }, "And the values match");
}

done_testing;
