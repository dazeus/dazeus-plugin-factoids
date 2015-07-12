#!/usr/bin/perl

use strict;
use warnings;
use DaZeus;

my ($socket, $network) = @ARGV;

if (!$socket or !$network) {
	warn "Usage: $0 socket network\n";
	exit 1;
}

my $dazeus = DaZeus->connect($socket);

my @keys = @{$dazeus->getPropertyKeys("perl.DazFactoids.factoid_", $network)};

foreach my $key (@keys) {
	print $key, "\n";
	my $value = $dazeus->getProperty($key, $network);
	$dazeus->setProperty($key, $value, $network);
}
