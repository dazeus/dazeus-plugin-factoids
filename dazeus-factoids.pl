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

use constant DB_PREFIX => "perl.DazFactoids.factoid_";

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

	my $factoid = getFactoid($1, $network, $sender, $channel);
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
		my $result = teachFactoid($factoid, $value, $network, $sender, $channel, %opts);
		if ($result == 0) {
			if ($command eq "reply") {
				$response = "Alright, I'll reply to " . $factoid . ".";
			} elsif ($command eq "forward") {
				$response = "Alright, I'll forward " . $factoid . ".";
			} elsif ($command eq "learn") {
				$response = "Alright, learned " . $factoid . ".";
			}
		} elsif ($result == 1) {
			$response = "I already know " . $factoid . "; it is ";

			# It is known.
			my $raw_factoid = getFactoid($factoid, $network, $sender, $channel, "value");
			if (defined($raw_factoid->{forward})) {
				$response .= "forwarded to ";
			}
			elsif (defined($raw_factoid->{reply})) {
				$response .= "replied to with ";
			}

			# Yes, it is known.
			$response .= "'" . $raw_factoid->{value} . "'!";
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
		my $result = forgetFactoid($arg, $network, $sender, $channel);
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

# Appending a string to an existing factoid.
$dazeus->subscribe_command("append" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		return reply("You'll have to give me something to work with, chap.", $network, $sender, $channel);
	}

	if (!($arg =~ /^['"](.+?)['"] to (.+)$/)) {
		return reply("To append something, please use '}append \"[your string]\" to [existing factoid]'.", $network, $sender, $channel);
	}

	my $amendment = $1;
	my $key = $2;

	my $factoid = getFactoid($key, $network, $sender, $channel, "value");
	if (!defined($factoid)) {
		return reply("I don't know anything about " . $2 . " yet. Please use }learn or }reply instead.", $network, $sender, $channel);
	}

	if (defined($factoid->{forward})) {
		return reply("I forward " . $key . " to " . $factoid->{value} . ". To avoid unintended consequences, please append to that factoid instead.", $network, $sender, $channel);
	}

	my $result = forgetFactoid($key, $network, $sender, $channel);
	if ($result == 2) {
		return reply("Factoid " . $key . " is currently blocked -- I cannot append anything to it.", $network, $sender, $channel);
	} else {
		my %opts;
		if (defined($factoid->{reply})) {
			$opts{reply} = 1;
		}

		my $new_value = $factoid->{value} . ' ' . $amendment, $sender;
		my $reply = teachFactoid($key, $new_value, $network, $sender, $channel, %opts);
		if ($reply == 0) {
			return reply("Alright, " . $key . "'s value is now '" . $new_value . "'.", $network, $sender, $channel);
		} else {
			return reply("Sorry chap, something unexpected went wrong!", $network, $sender, $channel);
		}
	}
});

# Prepending a string to an existing factoid.
$dazeus->subscribe_command("prepend" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		return reply("You'll have to give me something to work with, chap.", $network, $sender, $channel);
	}

	if (!($arg =~ /^['"](.+?)['"] to (.+)$/)) {
		return reply("To prepend something, please use '}prepend \"[your string]\" to [existing factoid]'.", $network, $sender, $channel);
	}

	my $amendment = $1;
	my $key = $2;

	my $factoid = getFactoid($key, $network, $sender, $channel, "value");
	if (!defined($factoid)) {
		return reply("I don't know anything about " . $key . " yet. Please use }learn or }reply instead.", $network, $sender, $channel);
	}

	if (defined($factoid->{forward})) {
		return reply("I forward " . $key . " to " . $factoid->{value} . ". To avoid unintended consequences, please prepand to that factoid instead.", $network, $sender, $channel);
	}

	my $result = forgetFactoid($key, $network, $sender, $channel);
	if ($result == 2) {
		return reply("Factoid " . $key . " is currently blocked -- I cannot prepend anything to it.", $network, $sender, $channel);
	} else {
		my %opts;
		if (defined($factoid->{reply})) {
			$opts{reply} = 1;
		}

		my $new_value = $amendment . ' ' . $factoid->{value}, $sender;
		my $reply = teachFactoid($key, $new_value, $network, $sender, $channel, %opts);
		if ($reply == 0) {
			return reply("Alright, " . $key . "'s value is now '" . $new_value . "'.", $network, $sender, $channel);
		} else {
			return reply("Sorry chap, something unexpected went wrong!", $network, $sender, $channel);
		}
	}
});

# Blocking a factoid.
$dazeus->subscribe_command("block" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		my $result = blockFactoid($arg, $network, $sender, $channel);
		if ($result == 0) {
			$response = "Okay, blocked " . $arg . ".";
		} elsif ($result == 1) {
			$response = "The factoid " . $arg . " was already blocked.";
		} elsif ($result == 2) {
			$response = "I don't know anything about " . $arg . " yet!";
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
		my $result = unblockFactoid($arg, $network, $sender, $channel);
		if ($result == 0) {
			$response = "Okay, unblocked " . $arg . ".";
		} elsif ($result == 1) {
			$response = "The factoid " . $arg . " wasn't blocked.";
		} elsif ($result == 2) {
			$response = "I don't know anything about " . $arg . " yet!";
		}
	}

	reply($response, $network, $sender, $channel);
});

# Getting information on a factoid.
$dazeus->subscribe_command("factoid" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;

	if (!defined($arg) || ($arg ne "stats" && $arg !~ /^\s*(info|debug|blame|whodunnit)\s*(.+)\s*$/)) {
		return reply("This command is intended for showing information on factoids. Please use 'factoid info X', 'factoid blame X', or 'factoid stats' -- where X is the factoid to be inspected.", $network, $sender, $channel);
	}

	if ($arg eq "stats") {
		return reply("I know " . countFactoids() . " factoids.", $network, $sender, $channel);
	} elsif ($1 eq "info" || $1 eq "debug") {
		my $value = getFactoid($2, $network, $sender, $channel, "value");
		if (!defined($value)) {
			reply("Sorry chap, '$2' is not a factoid. Yet.", $network, $sender, $channel);
		} else {
			my $response = "'$2' is a valid factoid. ";
			if (defined($value->{reply})) {
				$response .= "I reply to it with '" . $value->{value} . "'.";
			} elsif (defined($value->{forward})) {
				$response .= "I forward it to the factoid '" . $value->{value} . "'.";
			} else {
				$response .= "Its value is '" . $value->{value} . "'.";
			}
			return reply($response, $network, $sender, $channel);
		}
	} elsif ($1 eq "blame" || $1 eq "whodunnit") {
		return reply(blameFactoid($2, $network, $sender, $channel), $network, $sender, $channel);
	}
});

# Who dunnit?
$dazeus->subscribe_command("blame" => sub {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		$response = blameFactoid($arg, $network, $sender, $channel);
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
		my ($num_matches, @top5) = searchFactoids($network, $arg);
		if ($num_matches == 1) {
			$response = "I found one match: '" . $top5[0] . "': " . getFactoid($top5[0], $network, $sender, $channel, "short");
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
	my ($factoid, $network, $sender, $channel, $mode, @forwards) = @_;
	my $value = $dazeus->getProperty(DB_PREFIX . lc($factoid), $network);
	$mode = "normal" if (!defined($mode));

	if ($mode eq "value" || $mode eq "debug") {
		return $value;
	}

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
			return "Error: infinite forwarding detected. Trace: " . join(' -> ', @forwards) . ' -> ' . $fact;
		} else {
			return getFactoid($fact, $network, $sender, $channel, $mode, @forwards);
		}
	}

	# Finally, the fact we're looking for!
	return $mode eq "normal" && !defined($value->{reply}) ? $factoid . " is " . $fact : $fact;
}

sub blameFactoid {
	my ($factoid, $network, $sender, $channel) = @_;
	my $value = $dazeus->getProperty(DB_PREFIX . lc($factoid), $network);

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
	my ($factoid, $value, $network, $who, $channel, %opts) = @_;

	# Check whether we already know this one.
	if (defined($dazeus->getProperty(DB_PREFIX . lc($factoid), $network))) {
		print "DazFactoids: $who tried to teach me '$factoid' in $channel, but I already know it.\n";
		return 1;
	}

	print "DazFactoids: $who taught me '$factoid' in $channel with this value and opts:\n$value\n";
	print "-----\n" . Dumper(%opts) . "\n-----\n";

	# Let's learn it already!
	$dazeus->setProperty(DB_PREFIX . lc($factoid), { value => $value, creator => $who, timestamp => time(), %opts }, $network);
	return 0;
}

sub forgetFactoid {
	my ($factoid, $network, $sender, $channel) = @_;
	my $value = $dazeus->getProperty(DB_PREFIX . lc($factoid), $network);

	# Is this factoid known at all?
	if (!defined($value)) {
		print "DazFactoids: $sender tried to make me forget '$factoid' in $channel, but I don't know that factoid.\n";
		return 1;
	}

	# Blocked, perhaps?
	if (defined($value->{block})) {
		print "DazFactoids: $sender tried to make me forget '$factoid' in $channel, but it is blocked.\n";
		return 2;
	}

	print "DazFactoids: $sender made me forget '$factoid' in $channel - factoid had this value:\n";
	print "'" . $value->{value} . "'\n";

	# Let's forget about it already!
	$dazeus->unsetProperty(DB_PREFIX . lc($factoid), $network);
	return 0;
}

sub blockFactoid {
	my ($factoid, $network, $sender, $channel) = @_;
	my $value = $dazeus->getProperty(DB_PREFIX . lc($factoid), $network);

	if (!defined($value)) {
		return 2;
	}

	# Already blocked?
	if (defined($value->{block})) {
		return 1;
	}

	# Okay chaps, let's block this.
	$value->{block} = 1;
	$dazeus->setProperty(DB_PREFIX . lc($factoid), $value, $network);
	return 0;
}

sub unblockFactoid {
	my ($factoid, $network, $sender, $channel) = @_;
	my $value = $dazeus->getProperty(DB_PREFIX . lc($factoid), $network);

	# Not blocked?
	if (!defined($value->{block})) {
		return 1;
	}

	# Let's unblock it, then!
	delete $value->{block};
	$dazeus->setProperty(DB_PREFIX . lc($factoid), $value, $network);
	return 0;
}

sub countFactoids {
	my @keys = $dazeus->getPropertyKeys(DB_PREFIX);
	return scalar @keys;
}

sub searchFactoids {
	my ($network, $keyphase) = @_;
	my @keywords = split(/\s+/, $keyphase);
	my @keys = @{$dazeus->getPropertyKeys(DB_PREFIX . join('.*', @keywords), $network)};
	my %matches;
	my $num_matches = 0;

	# Alright, let's search!
	foreach my $factoid (@keys) {
		next if (!($factoid =~ /^@{[DB_PREFIX]}(.+)$/));
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
