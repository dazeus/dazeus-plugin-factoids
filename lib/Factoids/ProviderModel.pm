# Factoids plugin for DaZeus
# Copyright (C) 2012-2014  Aaron van Geffen <aaron@aaronweb.net>
# Blame functionality (C) 2013  Thom "TheGuyOfDoom" Wiggers <ret@rded.nl>
# Original module (C) 2007  Sjors Gielen <sjorsgielen@gmail.com>

package Factoids::ProviderModel;

use v5.10;
use strict;
use warnings;

use Data::Dumper;

use constant DB_PREFIX => "perl.DazFactoids.factoid_";

sub new {
	my $class = shift;
	my $self = {
		_dazeus => shift,
	};
	bless $self, $class;
	return $self;
}

sub _log {
	my $msg = shift;
	print "[factoids][" . localtime() . "] ", $msg, "\n";
}

sub get {
	my ($self, $factoid, $network, $sender, $channel, $mode, @forwards) = @_;
	my $value = $self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network);
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
			return $self->get($fact, $network, $sender, $channel, $mode, @forwards);
		}
	}

	# Finally, the fact we're looking for!
	return $mode eq "normal" && !defined($value->{reply}) ? $factoid . " is " . $fact : $fact;
}

sub blame {
	my ($self, $factoid, $network, $sender, $channel) = @_;
	my $value = $self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network);

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

sub teach {
	my ($self, $factoid, $value, $network, $who, $channel, %opts) = @_;

	# Check whether we already know this one.
	if (defined($self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network))) {
		_log("$who tried to teach me '$factoid' on $network, but I already know it.");;
		return 1;
	}

	_log("DazFactoids: $who taught me "
		. (defined($opts{reply}) ? 'to reply to ' : (defined($opts{forward}) ? 'to forward ' : ''))
		. "'$factoid' on $network; new value: '$value'");

	# Let's learn it already!
	$self->{_dazeus}->setProperty(DB_PREFIX . lc($factoid), { value => $value, creator => $who, timestamp => time(), %opts }, $network);
	return 0;
}

sub forget {
	my ($self, $factoid, $network, $sender, $channel) = @_;
	my $value = $self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network);

	# Is this factoid known at all?
	if (!defined($value)) {
		_log("$sender tried to make me forget '$factoid' on $network, but I don't know that factoid.");
		return 1;
	}

	# Blocked, perhaps?
	if (defined($value->{block})) {
		_log("$sender tried to make me forget '$factoid' on $network, but it is blocked.");
		return 2;
	}

	_log("$sender made me forget '$factoid' on $network - factoid had value: '" . $value->{value} . "'");

	# Let's forget about it already!
	$self->{_dazeus}->unsetProperty(DB_PREFIX . lc($factoid), $network);
	return 0;
}

sub block {
	my ($self, $factoid, $network, $sender, $channel) = @_;
	my $value = $self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network);

	if (!defined($value)) {
		return 2;
	}

	# Already blocked?
	if (defined($value->{block})) {
		return 1;
	}

	# Okay chaps, let's block this.
	$value->{block} = 1;
	$self->{_dazeus}->setProperty(DB_PREFIX . lc($factoid), $value, $network);
	return 0;
}

sub unblock {
	my ($self, $factoid, $network, $sender, $channel) = @_;
	my $value = $self->{_dazeus}->getProperty(DB_PREFIX . lc($factoid), $network);

	# Not blocked?
	if (!defined($value->{block})) {
		return 1;
	}

	# Let's unblock it, then!
	delete $value->{block};
	$self->{_dazeus}->setProperty(DB_PREFIX . lc($factoid), $value, $network);
	return 0;
}

sub count {
	my ($self, $network) = @_;

	# We currently cannot just fetch the number of keys, so we'll just have to fetch the keys themselves...
	my @keys = @{$self->{_dazeus}->getPropertyKeys(DB_PREFIX, $network)};
	return scalar @keys;
}

sub search {
	my ($self, $network, $keyphase) = @_;
	my @keywords = split(/\s+/, $keyphase);
	my @keys = @{$self->{_dazeus}->getPropertyKeys(DB_PREFIX, $network)};
	my %matches;
	my $num_matches = 0;

	# Alright, let's search!
	foreach my $factoid (@keys) {
		next if (!($factoid =~ /^@{[DB_PREFIX]}(.+)$/));
		$factoid = $1;

		my $relevance = 0;
		foreach my $keyword (@keywords) {
			next if (length($keyword) < 3);
			$relevance += length($keyword) if (index($factoid, $keyword) > -1);
		}

		next if $relevance == 0;
		$matches{$factoid} = $relevance / length($factoid);
		$num_matches++;
	}

	# Return the five most relevant results.
	my @sorted = sort { $matches{$b} <=> $matches{$a} } keys %matches;
	return ($num_matches, splice(@sorted, 0, 5));
}

1;
