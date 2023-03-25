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

{
	@list = let ($bird, %not_bird) = %source;
	
	is ($list[0], "squwak", "First item okay");
	is (scalar(@list), 9, "Correct number of items returned");
	is_deeply([sort @list[1, 3, 5, 7]], [sort keys %not_bird], "Keys are present");
	is_deeply([@list[2, 4, 6, 8]], [@not_bird{@list[1, 3, 5, 7]}], "Values are correct");
}

done_testing;
