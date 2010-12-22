#!/usr/bin/perl
# An IRC bot for managing events
# Written by John Resig
#   http://ejohn.org/

package WTPABot;
use base 'Bot::BasicBot';

# Includes, please install all ahead of time
# All can be found on CPAN

use Net::PingFM;
use Time::ParseDate;
use DateTime;
use Data::Dumper;
use Net::Google::Calendar;

# Configuration

# The IRC Server and Channel
my $server = 'irc.easymac.org';
my $chan = '#really';

# Details of the bot
my $nick = 'wtpa';
my $name = 'Party Time';
my $email = 'wheres-the-party-at@googlegroups.com';

# The time zones of all the events
my $TZ = 'America/New_York';
my $TZZ = 'EST';

# The name of the Google Calendar to update
my $cal_name = 'Where\'s the Party At?';

# The file where backups will be made
# If starting for the first time make a file that contains:
#  $VAR1 = [];
my $backup = 'backup.inc';
require $backup;

# Load in the authentication details
# The auth file should have 4 variables in it:
#  $GOOGLE_USER = '...'; # Google Username
#  $GOOGLE_PASS = '...'; # Google Password
#  $PING_USER = '...'; # PingFM Username
#  $PING_KEY = '...';  # PingFM Key
require 'auth.inc';

# Main Code

my @events = @{$VAR1};
my $cal;
my $p;

# Connect to Google Calendar and PingFM
sub init {
	# Connect to Google Calendar
	$cal = Net::Google::Calendar->new;
	$cal->login( $GOOGLE_USER, $GOOGLE_PASS );

	# We need to find the right calendar to use
	foreach ( $cal->get_calendars ) {
		if ( $_->title eq $cal_name ) {
			$cal->set_calendar( $_ );
		}
	}

	# Connect to PingFM
	$p = Net::PingFM->new(
		user_key => $PING_USER,
		api_key => $PING_KEY
	);

	$p->user_validate or die "Login failed.";
}

# Watch for changes to the topic
sub topic {
	my $self = shift;
	my $msg = shift;

	# If no user was specified (e.g. it was done before we entered the channel)
	if ( $msg->{who} eq "" ) {
		# Override the topic with ours
		$self->update_topic( $msg->{topic} );

	# If we didn't change the topic
	} elsif ( $msg->{who} ne $self->nick() ) {
		# Override the topic with ours
		$self->update_topic( $msg->{topic} );

		# And chastise the user who changed it
		$self->say(
			channel => $chan,
			body => "$msg->{who}: Please use me to update the topic!"
		);
	}
}

# A useful help message
sub help {
	return "Schedule an event! Tell me 'Place @ Time/Date' or 'Name of Event @ Place, Time/Date' " .
		"or 'cancel Name of Event' or 'update Name: New Name @ New Place, Time/Date' " .
		"or 'topic' to see the topic. Date format: http://j.mp/e7V35j";
}

# Watch for when messages are said
sub said {
	my $self = shift;
	my $msg = shift;

	$msg->{address} =~ s/[^\w]//g;

	# Check to see if the message was addressed to us
	if ( $msg->{address} eq $self->nick() || $msg->{address} eq "msg" ) {

		# Get the current topic
		if ( $msg->{body} eq "topic" ) {
			return $self->update_topic( 1 );

		# Is the user attempting to cancel an event
		} elsif ( $msg->{body} =~ /^cancel (.*)/i ) {
			my $name = $1;

			# Loop through all the events
			for ( my $i = 0; $i <= $#events; $i++ ) {
				# And look for one whose name matches
				if ( $events[$i]->{name} =~ /$name/i ) {
					print STDERR "Cancelling $events[$i]->{name}\n";

					# Be sure to remove the associated Google Calendar event
					eval {
						foreach my $item ( $cal->get_events() ) {
							if ( $item->id() eq $events[$i]->{id} ) {
								$cal->delete_entry( $item );
							}
						}
					};

					if ( my $err = $@ ) {
						$self->log_error( $msg->{who}, "Problem finding associated calendar entry." );

					} else {
						# Remove the event
						splice( @events, $i, 1 );

						# Update the topic
						$self->update_topic();
					}

					# Only remove the first found event
					last;
				}
			}

		# Update an event with new details
		} elsif ( $msg->{body} =~ /^update (.*?): ((.+) @ (?:(.+?), )?(.+))$/i ) {
			my $name = $1;
			my $desc = $2;
			my $start;
			my $all;
			my $data = {
				name => $3,
				place => $5 ? $4 : "",

				# This is where the date parsing is done
				when => parsedate($5 || $4, ZONE => $TZZ, PREFER_FUTURE => 1)
			};

			# We need to build the dates for the calendar
			eval {
				$start = DateTime->from_epoch( epoch => $data->{when}, time_zone => $TZ );

				# Crudely determine if this is an all-day event
				# (Assume that midnight events are all day)
				$all = $start->hour() == 0 && $start->minute() == 0;
			};

			if ( my $err = $@ ) {
				$self->log_error( $msg->{who}, "Problem with date format. See: http://j.mp/e7V35j" );
				return;
			}

			# Loop through all the events
			for ( my $i = 0; $i <= $#events; $i++ ) {
				my $event = $events[$i];

				# And look for one whose name matches
				if ( $event->{name} =~ /$name/i ) {
					print STDERR "Updating $event->{name}\n";

					# Be sure to update the associated Google Calendar event
					eval {
						foreach my $item ( $cal->get_events() ) {
							if ( $item->id() eq $event->{id} ) {
								# Update fields in calendar
								$item->title( $data->{name} );
								$item->content( $desc );
								$item->location( $data->{place} );

								# All events are two hours long by default
								$item->when( $start, $start + DateTime::Duration->new( hours => 2 ), $all );

								# Update the entry on the server
								$cal->update_entry( $item );
							}
						}
					};

					if ( my $err = $@ ) {
						$self->log_error( $msg->{who}, "Problem finding associated calendar entry." );

					} else {
						# Update the details of the event
						$event->{name} = $data->{name};
						$event->{place} = $data->{place};
						$event->{when} = $data->{when};
	
						# Update the topic
						$self->update_topic();
					}

					# Only update the first found event
					last;
				}
			}

		# Otherwise check to see if we're adding an event
		} elsif ( $msg->{body} =~ /^(.+) @ (?:(.+?), )?(.+)$/ ) {
			print STDERR "Adding new entry.\n";

			my $start;
			my $all;
			my $data = {
				name => $1,
				place => $3 ? $2 : "",

				# This is where the date parsing is done
				when => parsedate($3 || $2, ZONE => $TZZ, PREFER_FUTURE => 1)
			};

			# We need to build the dates for the calendar
			eval {
				$start = DateTime->from_epoch( epoch => $data->{when}, time_zone => $TZ );

				# Crudely determine if this is an all-day event
				# (Assume that midnight events are all day)
				$all = $start->hour() == 0 && $start->minute() == 0;
			};

			if ( my $err = $@ ) {
				$self->log_error( $msg->{who}, "Problem with date format. See: http://j.mp/e7V35j" );
				return;
			}

			# The date was built, now build the calendar entry
			eval {
				my $entry = Net::Google::Calendar::Entry->new();
				$entry->title( $data->{name} );
				$entry->content( $msg->{body} );
				$entry->location( $data->{place} );
				$entry->transparency( "transparent" );
				$entry->visibility( "public" );

				# All events are two hours long by default
				$entry->when( $start, $start + DateTime::Duration->new( hours => 2 ), $all );

				# The author is just a fake person
				my $author = Net::Google::Calendar::Person->new();
				$author->name( $name );
				$author->email( $email );
				$entry->author( $author );

				$entry = $cal->add_entry( $entry );

				# Save the ID generated by Google Calendar so we can remove it later
				$data->{id} = $entry->id();
			};

			if ( my $err = $@ ) {
				$self->log_error( $msg->{who}, "Problem saving calendar entry, please try again later." );

			} else {
				# The calendar was saved so save the data as well
				push( @events, $data );

				# Make sure all the events are saved in order
				@events = sort { $a->{when} <=> $b->{when} } @events;

				# Update the topic
				$self->update_topic();
			}

		# No recognizable comand was found, display help
		} else {
			return $self->help();
		}
	}

	# Return undefined to not display a response
	return;
}

# Simple routine for displaying error messages
sub log_error {
	my $self = shift;
	my $who = shift;
	my $msg = shift;

	print STDERR "ERROR: $msg\n";

	$self->say(
		channel => $chan,
		body => "$who: ERROR: $msg"
	);
}

# Simple method called every 5 seconds
# check for old events to remove
sub tick {
	my $self = shift;

	# Get the current day of the year for comparison
	my $now = DateTime->from_epoch( epoch => time(), time_zone => $TZ );
	my $cur = $now->doy();
	my $remove = 0;

	# Go through all the events
	for ( my $i = 0; $i <= $#events; $i++ ) {
		# Get their day of the year
		my $when = DateTime->from_epoch( epoch => $events[$i]->{when}, time_zone => $TZ );
		my $day = $when->doy();

		# If the event day is old we need to remove it
		if ( time() > $events[$i]->{when} && $day != $cur ) {
			print STDERR "Cleaning up $events[$i]->{name}\n";

			# Remove the event (but don't remove the calendar entry)
			splice( @events, $i, 1 );
			$i--;

			$remove++;
		}
	}

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
	my $topic = "";

	# Get the current day of the year
	my $now = DateTime->from_epoch( epoch => time(), time_zone => $TZ );
	my $cur = $now->doy();
	my $disp = "";

	# Go through all the events
	foreach my $event ( @events ) {
		# Get their day of the year
		my $when = DateTime->from_epoch( epoch => $event->{when}, time_zone => $TZ );
		my $day = $when->doy();

		# Make sure the date offset is handled correctly
		if ( $day < $cur && $event->{when} > time() ) {
			$day += 365;
		}

		# Only care about days within the next week
		if ( $day <= $cur + 7 ) {
			if ( $day != $disp ) {
				if ( $topic ne "" ) {
					$topic .= " | ";
				}

				# Display the day of the week as a prefix (e.g. "Tue: ")
				$topic .= ($day == $cur ? "" : $when->strftime("%a: "));

			} else {
				$topic .= ", ";
			}

			# Display the name and location of the event
			$topic .= "$event->{name} @" .
				# Don't display the place if one wasn't specified
				($event->{place} ? " $event->{place}" : "") .

				# Don't display a time when it's at midnight (assume a full-day event)
				($when->hour > 0 ? " " . $when->strftime(
					# Don't display the minutes when they're :00
					$when->minute > 0 ? "%l:%M%P" : "%l%P" ) : "");

		# Items further in the future are clumped together
		} else {
			$topic .= ($topic eq "" ? "" : $disp != $day ? " | Later: " : ", ");

			# Only display the name of the event and date (no location or time)
			$topic .= "$event->{name} " . $when->strftime("%b %e");
		}

		$disp = $day;
	}

	$topic =~ s/ +/ /g;

	# If no events, add a Richard-ism
	if ( $topic eq "" ) {
		$topic = "Embrace death.";
	}

	# A way to get at the current topic
	if ( $cur_topic == 1 ) {
		return $topic;
	}

	# The topic is identical to what's there, don't update
	if ( $topic eq $cur_topic ) {
		return;
	}

	print STDERR "Updating: $topic\n";

	# Backup the topic data
	open( F, ">$backup" );
	print F Dumper( \@events );
	close( F );

	# Update the topic in the channel
	$self->{IRCOBJ}->yield( sl_prioritized => PRI_NORMAL, "TOPIC $chan :$topic" );

	# Post the topic to PingFM
	eval {  
		$p->post( $topic );
	};

	if ( my $err = $@ ) {
		print STDERR "ERROR: $err\n";
	}
}

# Run the bot
package main;

my $bot = WTPABot->new(
	server => $server,
	channels => [ $chan ],
	nick => $nick,
	username => $nick,
	name => $name,
	port => 6697,
	ssl => 1
);

$bot->run();
