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
	calConnect();
	pingConnect();
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
	return "How to use me: http://github.com/jeresig/wtpa-bot";
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

		# Get the current topic
		} elsif ( $msg->{body} eq "topic" ) {
			return getTopic();

		# Is the user attempting to do add a place
		} elsif ( $msg->{body} =~ /^place add ([^ ]+) (.+)/i ) {
			addPlace( $1, $2 );

			$self->re( 0, $msg, "Place list updated." );

		# Is the user attempting to update a place
		} elsif ( $msg->{body} =~ /^place update (.*?): ([^ ]+) (.+)/i ) {
			updatePlace( $1, $2, $3 );

			$self->re( 0, $msg, "Place list updated." );

		# Dump a list of places
		} elsif ( $msg->{body} eq "places" && defined $ini->{places}{url} ) {
			$self->re( 0, $msg, $ini->{places}{url} );

		# Is the user attempting to cancel an event
		} elsif ( $msg->{body} =~ /^cancel (.*)/i ) {
			my $err = cancelEvent( $1 );
			
			if ( $err ) {
				$self->re( 1, $msg, $err );
			
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
				$self->re( 1, $msg, $err );
			
			} else {
				$self->update_topic();
			}

		# Otherwise check to see if we're adding an event
		} elsif ( $msg->{body} =~ /^(.+) @ (?:(.+?), )?(.+)$/ ) {
			print STDERR "Adding new entry.\n";
			
			my $err = addEvent({
				name => $1,
				place => $3 ? $2 : "",
				when => $3 ? $3 : $2
			});
			
			if ( $err ) {
				$self->re( 1, $msg, $err );
			
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
