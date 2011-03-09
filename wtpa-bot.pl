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

# Load places, connect to Google Calendar and PingFM
sub init {
	1;
}

# Watch for changes to the topic
sub topic {
	my $self = shift;
	my $msg = shift;

	# If no user was specified (e.g. it was done before we entered the channel)
	if ( !(defined $msg->{who}) || $msg->{who} eq "" ) {
		# Override the topic with ours
		$self->update_topic( $msg->{topic} );

	# If we didn't change the topic
	} elsif ( $msg->{who} ne $self->nick() ) {
		# Override the topic with ours
		$self->update_topic( $msg->{topic} );

		# And chastise the user who changed it
		$self->re( 1, $msg, "Please use me to update the topic!" );
	}
}

# A useful help message
sub help {
	return "Use: http://ejohn.org/wtpa/";
}

# Watch for when messages are said
sub said {
	my $self = shift;
	my $msg = shift;

	# Check to see if the message was addressed to us
	if ( defined $msg->{address} && ($msg->{address} eq $self->nick() || $msg->{address} eq "msg") ) {
		my $re = "";

		print STDERR "WHO: $msg->{who} MSG: $msg->{body}\n";

		# Dump a status report for today
		if ( $msg->{body} eq "" || $msg->{body} eq "wtpa" ) {
			$self->re( 0, $msg, getToday() );
		}

    } else {
		return $self->help();
	}

	# Return undefined to not display a response
	return;
}

# Simple routine for displaying error messages
sub re {
	my $self = shift;
	my $error = shift;
	my $orig = shift;
	my $msg = shift;

	if ( $error ) {
		print STDERR "ERROR: $msg\n";
		$msg = "ERROR: $msg";
	}

	$self->say( 
		who => $orig->{who},
		channel => $orig->{channel},
		body => ($orig->{channel} eq "msg" ? "" : "$orig->{who}: ") . $msg
	);
}

# Simple method called every 5 seconds
# check for old events to remove
sub tick {
	my $self = shift;
	my $remove = trimEvent();

	# Only update the topic if an item should be removed
	if ( $remove > 0 ) {
		$self->update_topic();
	}

	# Call the tick method again in 5 seconds
	return 5;
}

# Utility method for updating the topic
sub update_topic {
	my $self = shift;
	my $cur_topic = shift;
	my $topic = getTopic();

	# The topic is identical to what's there, don't update
	if ( defined $cur_topic && $topic eq $cur_topic ) {
		return;
	}

	print STDERR "Updating: $topic\n";

	# Update the topic in the channel
	$self->{IRCOBJ}->yield(
		sl_prioritized => 30,
		"TOPIC #" . $ini->{irc}{channel} . " :$topic" );
}
