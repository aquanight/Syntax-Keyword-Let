#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Syntax::Keyword::Let;

use B::Deparse;

use Syntax::Keyword::Let::Deparse;

my $deparser = B::Deparse->new();

sub is_deparsed {
	my ($sub, $exp, $name) = @_;

	my $got = $deparser->coderef2text($sub);
	$got =~ s/^\{\n(.*)\n\}$/$1/s;
	$got =~ s/^\s+//mg;
	1 while $got =~ s/^\s*(?:use|no) \w+.*\n//;
	$got =~ s/^BEGIN \{\n.*?\n\}\n//s;
	chomp $got;
	is ($got, $exp, $name);
}

my %source = (
	dog => "bark",
	cat => "meow",
	pig => "oink",
	rat => "squeak",
	bird => "squwak",
);

is_deparsed(
	sub { let ($dog) = %source; },
	q{let ($dog) = %source;},
	"basic deparsing of destructure"
);

is_deparsed(
	sub { let (dog => $different) = %source },
	q{let (dog => $different) = %source;},
	"with different key bareword"
);
my $key = "dog";
is_deparsed(

	sub { let ({ $key } => $different) = %source },
	q{let ({ $key } => $different) = %source;},
	"with expression key"
);

done_testing;
