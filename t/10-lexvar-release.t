#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Refcount;

use Syntax::Keyword::Let;

my %source = (
	dog => "bark",
	cat => "meow",
	pig => "oink",
	rat => "squeak",
	bird => "squwak",
	array => [],
);

is_oneref($source{array}, 'before test');
{
	let ($array) = %source;

}
is_oneref($source{array}, 'after test');

done_testing;
