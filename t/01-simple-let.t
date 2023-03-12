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
	let ($dog) = %source;

	is($dog, "bark");
}

# Verify that '$dog' was a lexical:
{
	my $r = eval 'undef $dog; 1;';
	my $err = $@;
	ok(!$r, 'failed under strict');
	ok($err =~ m/Global symbol "\$dog" requires explicit package name/);
}

{
	# Multiple variables, in arbitrary order:
	let ($cat, $pig, $bird, $rat) = %source;

	is ($cat, "meow");
	is ($pig, "oink");
	is ($rat, "squeak");
	is ($bird, "squwak");
}

{
	let ($missing) = %source;

	ok(!defined $missing);
}

done_testing;
