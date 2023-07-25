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

{
	let {dog => $dog} = $source;

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
	let {cat => $cat, pig => $pig, bird => $bird, rat => $rat} = $source;

	is ($cat, "meow");
	is ($pig, "oink");
	is ($rat, "squeak");
	is ($bird, "squwak");
}

{
	# When using your own specified key, no reason the variable has to be named anything in particular:
	let {cat => $meow} = $source;
	is ($meow, "meow");
}

done_testing;
