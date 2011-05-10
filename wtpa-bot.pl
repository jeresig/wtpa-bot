#!/usr/bin/perl
# An IRC bot for managing events
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

utilInit( $ini );

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

our $curTopic = "";

# Load places, connect to Google Calendar and PingFM
sub init {
	calConnect();
	pingConnect();
}

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
	return "How to use me: http://github.com/jeresig/wtpa-bot Also: http://ejohn.org/wtpa/";
}

# Watch for when messages are said
sub said {
	my ( $self, $msg ) = @_;

	# Check to see if the message was addressed to us
	if ( defined $msg->{address} && ($msg->{address} eq $self->nick() || $msg->{address} eq "msg") ) {
		my $re = "";

		print STDERR "WHO: $msg->{who} MSG: $msg->{body}\n";

		# Dump a status report for today
		if ( $msg->{body} eq "" || $msg->{body} eq "wtpa" ) {
			return getToday();

		# Is the user attempting to cancel an event
		} elsif ( $msg->{body} =~ /^cancel (.*)/i ) {
			my $err = cancelEvent( $1 );
			
			if ( $err ) {
				return $err;
			
			} else {
				$self->update_topic();
			}

		# Update an event with new details
		} elsif ( $msg->{body} =~ /^update (.*?): ((.+) @ (?:(.+?), )?(.+))$/i ) {
			my $err = updateEvent( $1, $2, {
				name => $3,
				place => $5 ? $4 : "",
				when => $5 || $4
			});
			
			if ( $err ) {
				return $err;
			
			} else {
				$self->update_topic();
			}

		# Otherwise check to see if we're adding an event
		} elsif ( $msg->{body} =~ /^(.+) @ (?:(.+?), )?(.+)$/ ) {
			my $err = addEvent({
				name => $1,
				place => $3 ? $2 : "",
				when => $3 ? $3 : $2
			});
			
			if ( $err ) {
				return $err;
			
			} else {
				# Update the topic
				$self->update_topic();
			}

    } else {
			return $self->help();
		}
	}

	# Return undefined to not display a response
	return;
}

# Simple method called every 30 seconds to update the topic with the new value
sub tick {
	my $self = shift;

	$self->update_topic();

	# Call the tick method again in 5 seconds
	return 30;
}

# Utility method for updating the topic
sub update_topic {
	my ( $self ) = @_;

	# Pull in the event data from the server
	loadBackup();
	loadPlaces();

	# Figure out what the new topic should be
	my $topic = getTopic();

	# The topic is identical to what's there, don't update
	if ( defined $curTopic && index( $topic, $curTopic ) == 0 ) {
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
