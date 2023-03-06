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
	my $key = "dog";
	let ({$key} => $dog) = %source;

	is($dog, "bark");
}

# Verify that '$dog' was a lexical:
{
	my $r = eval 'undef $dog; 1;';
	my $err = $@;
	ok(!$r, 'failed under strict');
	ok($err =~ m/Global symbol "\$dog" requires explicit package name/);
}

done_testing;
