#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Syntax::Keyword::Let;

my $source = {
	dog => "bark",
	cat => "meow",
	pig => "oink",
	rat => "squeak",
	bird => "squwak",
};

my $src2 = [ sort keys %$source ];

{
	my $cr;
	my $r;
	# Control test:
	$cr = (my ($cx, $cy) = @$src2);

	$r = (let [ $x, $y ] = $src2);

	is($x, $cx);
	is($y, $cy);

	is($cr, 5); # Yes we are testing a property of baseline perl - intended to demonstrate the difference between let and my here
	is($r, 2);
}

{
	let [ $_1, $_2, $_3, $_4, $_5, $_6 ] = $src2;
	ok(!defined($_6));
}

{
	let [$x, $y, @remain] = $src2;

	is_deeply(\@remain, [ $src2->@[2 .. $#$src2 ] ]);
}

done_testing;
