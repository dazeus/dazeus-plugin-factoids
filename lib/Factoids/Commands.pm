# Factoids plugin for DaZeus
# Copyright (C) 2012-2014  Aaron van Geffen <aaron@aaronweb.net>
# Blame functionality (C) 2013  Thom "TheGuyOfDoom" Wiggers <ret@rded.nl>
# Original module (C) 2007  Sjors Gielen <sjorsgielen@gmail.com>

package Factoids;
our @EXPORT_OK = qw(registerCommands);

sub registerCommands {
	my $dazeus = pop @_;
	$dazeus->subscribe("PRIVMSG" => \&commandLookUp);
	$dazeus->subscribe_command("learn", \&commandLearn);
	$dazeus->subscribe_command("reply", \&commandLearn);
	$dazeus->subscribe_command("forward", \&commandLearn);
	$dazeus->subscribe_command("forget" => \&commandForget);
	$dazeus->subscribe_command("append" => \&commandAppend);
	$dazeus->subscribe_command("prepend" => \&commandPrepend);
	$dazeus->subscribe_command("block" => \&commandBlock);
	$dazeus->subscribe_command("unblock" => \&commandUnblock);
	$dazeus->subscribe_command("factoid" => \&commandFactoid);
	$dazeus->subscribe_command("blame" => \&commandBlame);
	$dazeus->subscribe_command("search" => \&commandSearch);
}

# Handles looking up factoids.
sub commandLookUp {
	my ($self, $event) = @_;
	my ($network, $sender, $channel, $msg) = @{$event->{params}};

	# Not a factoid request? Ignore the message.
	if ($msg !~ /^\](.+)$/) {
		return;
	}

	my $factoid = getFactoid($1, $network, $sender, $channel);
	reply($factoid, $network, $sender, $channel);
};

# Handles teaching factoids.
sub commandLearn {
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
sub commandForget {
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
};

# Appending a string to an existing factoid.
sub commandAppend {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		return reply("You'll have to give me something to work with, chap.", $network, $sender, $channel);
	}

	if (!($arg =~ /^['"](.+?)['"] to (.+)$/) and !($arg =~ /^([^\s]+) to (.+)/)) {
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

		if ($amendment =~ /^[\s\w]/) {
			$amendment = ' ' . $amendment;
		}

		my $new_value = $factoid->{value} . $amendment;
		my $reply = teachFactoid($key, $new_value, $network, $sender, $channel, %opts);
		if ($reply == 0) {
			return reply("Alright, " . $key . "'s value is now '" . $new_value . "'.", $network, $sender, $channel);
		} else {
			return reply("Sorry chap, something unexpected went wrong!", $network, $sender, $channel);
		}
	}
};

# Prepending a string to an existing factoid.
sub commandPrepend {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		return reply("You'll have to give me something to work with, chap.", $network, $sender, $channel);
	}

	if (!($arg =~ /^['"](.+?)['"] to (.+)$/) and !($arg =~ /^([^\s]+) to (.+)/)) {
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

		if ($amendment =~ /[^\s]$/) {
			$amendment = $amendment . ' ';
		}

		my $new_value = $amendment . $factoid->{value};
		my $reply = teachFactoid($key, $new_value, $network, $sender, $channel, %opts);
		if ($reply == 0) {
			return reply("Alright, " . $key . "'s value is now '" . $new_value . "'.", $network, $sender, $channel);
		} else {
			return reply("Sorry chap, something unexpected went wrong!", $network, $sender, $channel);
		}
	}
};

# Blocking a factoid.
sub commandBlock {
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
};

# Unblocking a factoid.
sub commandUnblock {
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
};

# Getting information on a factoid.
sub commandFactoid {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;

	if (!defined($arg) || ($arg ne "stats" && $arg !~ /^\s*(info|debug|blame|whodunnit)\s*(.+)\s*$/)) {
		return reply("This command is intended for showing information on factoids. Please use 'factoid info X', 'factoid blame X', or 'factoid stats' -- where X is the factoid to be inspected.", $network, $sender, $channel);
	}

	if ($arg eq "stats") {
		return reply("I know " . countFactoids($network) . " factoids.", $network, $sender, $channel);
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
};

# Who dunnit?
sub commandBlame {
	my ($self, $network, $sender, $channel, $command, $arg) = @_;
	my $response;

	if (!defined($arg) || $arg eq "") {
		$response = "You'll have to give me something to work with, chap.";
	} else {
		$response = blameFactoid($arg, $network, $sender, $channel);
	}

	reply($response, $network, $sender, $channel);
};

# Search for factoids.
sub commandSearch {
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
};
