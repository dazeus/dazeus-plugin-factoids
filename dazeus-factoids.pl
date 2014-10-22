#!/usr/bin/perl
# Factoids plugin for DaZeus
# Copyright (C) 2012-2014  Aaron van Geffen <aaron@aaronweb.net>
# Blame functionality (C) 2013  Thom "TheGuyOfDoom" Wiggers <ret@rded.nl>
# Original module (C) 2007  Sjors Gielen <sjorsgielen@gmail.com>

use strict;
use warnings;
use lib './lib';
use v5.10;

use DaZeus;
use Factoids::Commands;
use constant DB_PREFIX => "perl.DazFactoids.factoid_";

my ($socket) = @ARGV;

if (!$socket) {
	warn "Usage: $0 socket\n";
	exit 1;
}

print "Now connecting to $socket...";
my $dazeus = DaZeus->connect($socket);
print " connected!\n";

registerCommands($dazeus);

while($dazeus->handleEvents()) {}
