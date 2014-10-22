# Factoids plugin for DaZeus
# Copyright (C) 2012-2014  Aaron van Geffen <aaron@aaronweb.net>
# Blame functionality (C) 2013  Thom "TheGuyOfDoom" Wiggers <ret@rded.nl>
# Original module (C) 2007  Sjors Gielen <sjorsgielen@gmail.com>

package Factoids;
require Exporter;
our @ISA = ('Exporter');
our @EXPORT = qw(reply getFactoid blameFactoid teachFactoid forgetFactoid blockFactoid unblockFactoid countFactoids searchFactoids checkKeywords);

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
	my ($network) = @_;
	my @keys = $dazeus->getPropertyKeys(DB_PREFIX, $network);
	return scalar @keys;
}

sub searchFactoids {
	my ($network, $keyphase) = @_;
	my @keywords = split(/\s+/, $keyphase);
	my @keys = @{$dazeus->getPropertyKeys(DB_PREFIX, $network)};
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
