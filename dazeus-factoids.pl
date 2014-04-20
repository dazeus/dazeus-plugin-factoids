#!/usr/bin/perl
# Factoids plugin for DaZeus
# Copyright (C) 2012-2014  Aaron van Geffen <aaron@aaronweb.net>
# Blame functionality (C) 2013  Thom "TheGuyOfDoom" Wiggers <ret@rded.nl>
# Original module (C) 2007  Sjors Gielen <sjorsgielen@gmail.com>

use strict;
use warnings;
use DaZeus;
use Data::Dumper;
use v5.10;

my ($socket) = @ARGV;

if (!$socket) {
	warn "Usage: $0 socket\n";
	exit 1;
}

print "Now connecting to $socket...";
my $dazeus = DaZeus->connect($socket);
print " connected!\n";

#####################################################################
#                       CONTROLLER FUNCTIONS
#####################################################################

# Handles looking up factoids.
$dazeus->subscribe("PRIVMSG" => sub {
	my ($self, $event) = @_;
	my ($network, $sender, $channel, $msg) = @{$event->{params}};

	# Not a factoid request? Ignore the message.
	if ($msg !~ /^\](.+)$/) {
		return;
	}

	my $factoid = getFactoid($1, $sender, $channel);
	reply($factoid, $network, $sender, $channel);
});

# Learning, replying or forwarding factoids.
$dazeus->subscribe_command("learn", \&parseLearnCommand);
$dazeus->subscribe_command("reply", \&parseLearnCommand);
$dazeus->subscribe_command("forward", \&parseLearnCommand);

# Told function, a.k.a. "the controller".
sub parseLearnCommand {
	my ($self, $network, $sender, $channel, $command, $line) = @_;

	# Let's try to keep this as English as possible, okay?
	my ($factoid, $value, $separator);
	if ($command eq "reply") {
		($factoid, $value) = $line =~ /^(.+?)\s+with\s+(.+)$/;
		$separator = "with";
	} elsif ($command eq "forward") {
		($factoid, $value) = $line =~ /^(.+?)\s+to\s+(.+)$/;
		$separator = "to";
	} else {
		($factoid, $value) = $line =~ /^(.+?)\s+is\s+(.+)$/;
		$separator = "is";
	}

	# A few sanity checks...
	my $response;
	if (!defined($factoid)) {
		$response = "The " . $command . " command is intended for learning factoids. Please use '}" . $command . " <factoid> " . $separator . " <value>' to add one.";
	} elsif ($value =~ /dcc/i) {
		$response = "The value contains blocked words (dcc)." ;
	} else {
		# Make direct replies and factoid forwards possible, too...
		my %opts;
		if ($command eq "reply") {
			$opts{reply} = 1;
		} elsif ($command eq "forward") {
			$opts{forward} = 1;
		}

		# Teach it!
		my $result = teachFactoid($factoid, $value, $sender, $channel, %opts);
		if ($result == 0) {
			if ($command eq "reply") {
				$response = "Alright, I'll reply to " . $factoid . ".";
			} elsif ($command eq "forward") {
				$response = "Alright, I'll forward " . $factoid . ".";
			} elsif ($command eq "learn") {
				$response = "Alright, learned " . $factoid . ".";
			}
		} elsif ($result == 1) {
			$response = "I already know " . $factoid . "; it is '" . getFactoid($factoid, $sender, $channel, "short") . "'!";
		}
	}

	reply($response, $network, $sender, $channel);
}

# Forgetting factoids
$dazeus->subscribe_command("forget" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		my $result = forgetFactoid($arg, $sender, $channel);
		if ($result == 0) {
			$response = "Alright, forgot all about " . $arg . ".";
		} elsif ($result == 1) {
			$response = "I don't know anything about " . $arg . ".";
		} elsif ($result == 2) {
			$response = "The factoid '" . $arg . "' is blocked; I cannot forget it.";
		}
	}

	reply($response, $network, $sender, $channel);
});

# Blocking a factoid.
$dazeus->subscribe_command("block" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		my $result = blockFactoid($arg, $sender, $channel);
		if ($result == 0) {
			$response = "Okay, blocked " . $arg . ".";
		} elsif ($result == 1) {
			$response = "The factoid " . $arg . " was already blocked.";
		}
	}

	reply($response, $network, $sender, $channel);
});

# Unblocking a factoid.
$dazeus->subscribe_command("unblock" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		my $result = blockFactoid($arg, $sender, $channel);
		if ($result == 0) {
			$response = "Okay, unblocked " . $arg . ".";
		} elsif ($result == 1) {
			$response = "The factoid " . $arg . " wasn't blocked.";
		}
	}

	reply($response, $network, $sender, $channel);
});

# Statistics! Everyone's favourite biatch.
$dazeus->subscribe_command("factoidstats" => sub {
	my ($self, $network, $sender, $channel, $command, undef) = @_;
	my $response = "I know " . countFactoids() . " factoids.";

	reply($response, $network, $sender, $channel);
});

# Who dunnit?
$dazeus->subscribe_command("blame" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		$response = blameFactoid($arg);
	}

	reply($response, $network, $sender, $channel);
});

# Search for factoids.
$dazeus->subscribe_command("search" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} elsif (!checkKeywords($arg)) {
		$response = "No valid keywords were provided. Keywords must be at least three characters long; shorter ones will be ignored.";
	} else {
		my ($num_matches, @top5) = searchFactoids($arg);
		if ($num_matches == 1) {
			$response = "I found one match: '" . $top5[0] . "': " . getFactoid($top5[0], $sender, $channel, "short");
		} elsif ($num_matches > 0) {
			$response = "I found " . $num_matches . " factoids. Top " . (scalar @top5) . ": '" . join("', '", @top5) . "'.";
		} else {
			$response = "Sorry, I couldn't find any matches.";
		}
	}

	reply($response, $network, $sender, $channel);
});

while($dazeus->handleEvents()) {}

#####################################################################
#                          MODEL FUNCTIONS
#####################################################################

sub reply {
	my ($response, $network, $sender, $channel) = @_;

	if ($channel eq $dazeus->getNick($network)) {
		$dazeus->message($network, $sender, $response);
	} else {
		$dazeus->message($network, $channel, $response);
	}
}

sub getFactoid {
	my ($factoid, $sender, $channel, $mode, @forwards) = @_;
	my $value = $dazeus->getProperty("factoid_" . lc($factoid));
	$mode = "normal" if (!defined($mode));

	# Do we know this at all?
	if (!defined($value)) {
		return ($mode eq "normal" ? "I don't know $factoid." : undef);
	}

	# Fill in some placeholders.
	my $fact = $value->{value};
	$fact =~ s/<who>/$sender/gi;
	$fact =~ s/<channel>/$channel/gi;
	push @forwards, $factoid;

	# Traverse forwards if necessary.
	if ($value->{forward}) {
		if ($fact ~~ @forwards) {
			return "[ERROR] Factoid deeplink detected";
		} else {
			return getFactoid($fact, $sender, $channel, $mode, @forwards);
		}
	}

	# Finally, the fact we're looking for!
	return $mode eq "normal" && !defined($value->{reply}) ? $factoid . " is " . $fact : $fact;
}

sub blameFactoid {
	my ($factoid, $mess) = @_;
	my $value = $dazeus->getProperty("factoid_" . lc($factoid));
	my $who = $mess->{who};
	my $channel = $mess->{channel};

	# Do we know this at all?
	if (!defined($value)) {
		return "I don't know $factoid.";
	}
	my $creator = $value->{creator};
	if (!defined($creator)) {
		return "This factoid was set by a ninja";
	}

	$creator =~ s/^(..)/$1~/;
	return $factoid . " was set by " . $value->{creator} . " at " . localtime($value->{'timestamp'}) . ".";
}

sub teachFactoid {
	my ($factoid, $value, $who, $channel, %opts) = @_;

	# Check whether we already know this one.
	if (defined($dazeus->getProperty("factoid_" . lc($factoid)))) {
		print "DazFactoids: $who tried to teach me $factoid in $channel, but I already know it.\n";
		return 1;
	}

	print "DazFactoids: $who taught me $factoid in $channel with this value and opts:\n$value\n";
	print "-----\n" . Dumper(%opts) . "\n-----\n";

	# Let's learn it already!
	$dazeus->setProperty("factoid_" . lc($factoid), { value => $value, creator => $who, timestamp => time(), %opts });
	return 0;
}

sub forgetFactoid {
	my ($factoid, $who, $channel) = @_;
	my $value = $dazeus->getProperty("factoid_" . lc($factoid));

	# Is this a factoid known at all?
	if (!defined($value)) {
		print "DazFactoids: $who tried to make me forget $factoid in $channel, but I don't know that factoid.\n";
		return 1;
	}

	# Blocked, perhaps?
	if (defined($value->{block})) {
		print "DazFactoids: $who tried to make me forget $factoid in $channel, but it is blocked.\n";
		return 2;
	}

	print "DazFactoids: $who made me forget $factoid in $channel - factoid had this value:\n";
	print "'" . $value->{value} . "'\n";

	# Let's forget about it already!
	$dazeus->unsetProperty("factoid_" . lc($factoid));
	return 0;
}

sub blockFactoid {
	my ($factoid, $who, $channel) = @_;
	my $value = $dazeus->getProperty("factoid_" . lc($factoid));

	# Already blocked?
	if (defined($value->{block})) {
		return 1;
	}

	# Okay chaps, let's block this.
	$value->{block} = 1;
	$dazeus->setProperty("factoid_" . lc($factoid), $value);
	return 0;
}

sub unblockFactoid {
	my ($factoid, $who, $channel) = @_;
	my $value = $dazeus->getProperty("factoid_" . lc($factoid));

	# Not blocked?
	if (!defined($value->{block})) {
		return 1;
	}

	# Let's unblock it, then!
	delete $value->{block};
	$dazeus->setProperty("factoid_" . lc($factoid), $value);
	return 0;
}

sub countFactoids {
	my @keys = $dazeus->getPropertyKeys();
	my $num_factoids = 0;

	foreach (@keys) {
		++$num_factoids if ($_ =~ /^factoid_(.+)$/);
	}
	return $num_factoids;
}

sub searchFactoids {
	my ($keyphase) = @_;
	my @keywords = split(/\s+/, $keyphase);
	my @keys = $dazeus->getPropertyKeys();
	my %matches;
	my $num_matches = 0;

	# Alright, let's search!
	foreach my $factoid (@keys) {
		next if (!($factoid =~ /^factoid_(.+)$/));
		$factoid = $1;

		my $relevance = 0;
		foreach my $keyword (@keywords) {
			next if (length($keyword) < 3);
			$relevance++ if (index($factoid, $keyword) > -1);
		}

		next if $relevance == 0;
		$matches{$factoid} = $relevance;
		$num_matches++;
	}

	# Return the five most relevant results.
	my @sorted = sort { $matches{$b} <=> $matches{$a} } keys %matches;
	return ($num_matches, splice(@sorted, 0, 5));
}

sub checkKeywords {
	my ($keyphrase) = @_;
	my @keywords = split(/\s+/, $keyphrase);

	foreach my $keyword (@keywords) {
		return 1 if length $keyword >= 3;
	}

	return 0;
}
