#!/usr/bin/perl
# An IRC bot for updating the topic of a channel
# to show upcoming events.
# Written by John Resig
#   http://ejohn.org/

use 5.010;
use strict;
use warnings;

package main;

use WTPA;
use Config::Abstract::Ini;

our $ini = (new Config::Abstract::Ini( 'config.ini' ))->get_all_settings;

# We're pulling from a remote URL instead of a local file
$ini->{config}{remoteBackup} = "http://ejohn.org/files/wtpa/events.json";

$WTPA::ini = $ini;

my $bot = WTPABot->new(
	server => $ini->{irc}{server},
	channels => [ '#' . $ini->{irc}{channel} ],
	nick => $ini->{irc}{nick},
	username => $ini->{irc}{nick},
	name => $ini->{irc}{name},
	port => $ini->{irc}{port},
	ssl => $ini->{irc}{ssl}
);

$bot->run();

package WTPABot;
use base 'Bot::BasicBot';

use WTPA;
use LWP::Simple;

our $curTopic = "";

# Watch for changes to the topic
sub topic {
	my ( $self, $msg ) = @_;
	
	# Remember what the new topic is, so we don't set it again
	$curTopic = $msg->{topic};

	# Override the topic with ours
	$self->update_topic();
}

# A useful help message
sub help {
	return "Use: http://ejohn.org/wtpa/";
}

# Watch for when messages are said
sub said {
	my ( $self, $msg ) = @_;

	# Check to see if the message was addressed to us
	if ( defined $msg->{address} && ($msg->{address} eq $self->nick() || $msg->{address} eq "msg") ) {
		# Dump a status report for today
		if ( $msg->{body} eq "" || $msg->{body} eq "wtpa" ) {
			return getToday();
		}
    }

	# Return undefined to not display a response
	return;
}

# Simple method called every 30 seconds to update the topic with the new value
sub tick {
	my $self = shift;

	$self->update_topic();

	# Call the tick method again in 30 seconds
	return 30;
}

# Utility method for updating the topic
sub update_topic {
	my ( $self ) = @_;
	
	# Pull in the event data from the server
	loadBackup();
	
	# Figure out what the new topic should be
	my $topic = getTopic();

	# The topic is identical to what's there, don't update
	if ( $topic eq $curTopic ) {
		return;
	}

	print STDERR "Updating: $topic\n";

	# Update the topic in the channel
	$self->{IRCOBJ}->yield(
		sl_prioritized => 30,
		"TOPIC #" . $ini->{irc}{channel} . " :$topic"
	);
	
	# Remember what the new topic is, so we don't set it again
	$curTopic = $topic;
}