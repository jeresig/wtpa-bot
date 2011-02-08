#!/usr/bin/perl
# An IRC bot for managing events
# Written by John Resig
#   http://ejohn.org/

use 5.010;
use strict;
use warnings;

package main;

our $ini = (new Config::Abstract::Ini( 'config.ini' ))->get_all_settings;

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

# Includes, please install all ahead of time
# All can be found on CPAN

use JSON;
use DateTime;
use Net::PingFM;
use Time::ParseDate;
use WWW::Shorten::Bitly;
use Net::Google::Calendar;
use Config::Abstract::Ini;

# Main Code

my @events = ();
my %places = ();
my $cal;
my $ping;

# Load places, connect to Google Calendar and PingFM
sub init {
	# Load the old data from the backup file
	open( JSON, $ini->{config}{backup} );
	my $json = <JSON>;
	@events = @{$json ne "" ? decode_json( $json ) : []};
	close( JSON );

	# Load in all the addresses being used
	open( JSON, $ini->{places}{backup} );
	$json = <JSON>;
	%places = %{$json ne "" ? decode_json( $json ) : {}};
	close( JSON );

	# Connect to Google Calendar
	if ( defined $ini->{google}{user} ) {
		$cal = Net::Google::Calendar->new;
		$cal->login(
			$ini->{google}{user},
			$ini->{google}{pass}
		);

		# We need to find the right calendar to use
		foreach ( $cal->get_calendars ) {
			if ( $_->title eq $ini->{google}{calendar_name} ) {
				$cal->set_calendar( $_ );
			}
		}
	}

	# Connect to PingFM
	if ( defined $ini->{ping}{user} ) {
		$ping = Net::PingFM->new(
			user_key => $ini->{ping}{user},
			api_key => $ini->{ping}{key}
		);

		$ping->user_validate or die "Login failed.";
	}
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
			# Get the current day of the year
			my $now = $self->get_time( time() );
			my $cur = $now->doy();

			# Go through all the events
			foreach my $event ( @events ) {
				# Get their day of the year
				my $when = $self->get_time( $event->{when} );
				my $day = $when->doy();

				if ( $day == $cur ) {
					my $place = $self->find_place( $event );
					my $url = "";

					if ( defined $ini->{bitly}{user} && $place ne $event->{name} &&
							(!(defined $event->{place}) || $place ne $event->{place}) ) {
						$url = makeashorterlink( "http://maps.google.com/maps?q=$place",
							$ini->{bitly}{user},
							$ini->{bitly}{key}
						);
					}

					if ( $re ) {
						$re .= ", ";
					}

					# Display the name and location of the event
					$re .= "$event->{name} " .

						# Don't display a time when it's at midnight (assume a full-day event)
						($when->hour > 0 ? $when->strftime(
							# Don't display the minutes when they're :00
							$when->minute > 0 ? "%l:%M%P" : "%l%P" ) : "") .

						($event->{place} || $url ? " @ " : "") .

						# Don't display the place if one wasn't specified
						($event->{place} ? " $event->{place}" : "") .
						($url ? " ($place $url)" : "");
				}
			}

			$re =~ s/ +/ /g;

			$self->re( 0, $msg, $re || "No party today!" );

		# Get the current topic
		} elsif ( $msg->{body} eq "topic" ) {
			return $self->update_topic( "1" );

		# Is the user attempting to do add a place
		} elsif ( $msg->{body} =~ /^place add ([^ ]+) (.+)/i ) {
			my $new_place = $1;
			my $new_address = $2;

			$places{ $new_place } = $new_address;

			$self->save_places( $msg );

		# Is the user attempting to update a place
		} elsif ( $msg->{body} =~ /^place update (.*?): ([^ ]+) (.+)/i ) {
			my $match = $1;
			my $new_place = $2;
			my $new_address = $3;

			# Look through places, finding the first one to replace
			foreach my $place ( sort keys %places ) {
				if ( $place =~ /$match/i ) {
					delete $places{ $place };

					$places{ $new_place } = $new_address;
				}

				last;
			}

			$self->save_places( $msg );

		# Dump a list of places
		} elsif ( $msg->{body} eq "places" && defined $ini->{places}{url} ) {
			$self->re( 0, $msg, $ini->{places}{url} );

		# Is the user attempting to cancel an event
		} elsif ( $msg->{body} =~ /^cancel (.*)/i ) {
			my $name = $1;

			# Loop through all the events
			for ( my $i = 0; $i <= $#events; $i++ ) {
				# And look for one whose name matches
				if ( $events[$i]->{name} =~ /$name/i ) {
					print STDERR "Cancelling $events[$i]->{name}\n";

					# Be sure to remove the associated Google Calendar event
					if ( defined $cal ) {
						eval {
							foreach my $item ( $cal->get_events() ) {
								if ( $item->id() eq $events[$i]->{id} ) {
									$cal->delete_entry( $item );
								}
							}
						};

						if ( my $err = $@ ) {
							$self->re( 1, $msg, "Problem finding associated calendar entry." );
							last;
						}
					}

					# Remove the event
					splice( @events, $i, 1 );

					# Update the topic
					$self->update_topic();

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
				when => $self->parse_date( $5 || $4 )
			};

			# We need to build the dates for the calendar
			eval {
				$start = $self->get_time( $data->{when} );

				# Crudely determine if this is an all-day event
				# (Assume that midnight events are all day)
				$all = $start->hour() == 0 && $start->minute() == 0;
			};

			if ( my $err = $@ ) {
				$self->re( 1, $msg, "Problem with date format. See: http://j.mp/e7V35j" );
				return;
			}

			# Loop through all the events
			for ( my $i = 0; $i <= $#events; $i++ ) {
				my $event = $events[$i];

				# And look for one whose name matches
				if ( $event->{name} =~ /$name/i ) {
					print STDERR "Updating $event->{name}\n";

					# Be sure to update the associated Google Calendar event
					if ( defined $cal ) {
						eval {
							foreach my $item ( $cal->get_events() ) {
								if ( $item->id() eq $event->{id} ) {
									# Update fields in calendar
									$item->title( $data->{name} );
									$item->content( $desc );
									$item->location( $self->find_place( $data ) );

									# All events are two hours long by default
									$item->when( $start, $start + DateTime::Duration->new( hours => 2 ), $all );

									# Update the entry on the server
									$cal->update_entry( $item );
								}
							}
						};

						if ( my $err = $@ ) {
							$self->re( 1, $msg, "Problem finding associated calendar entry." );
							last;
						}
					}

					# Update the details of the event
					$event->{name} = $data->{name};
					$event->{place} = $data->{place};
					$event->{when} = $data->{when};
	
					# Update the topic
					$self->update_topic();

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
				when => $self->parse_date( $3 ? $3 : $2 )
			};

			# We need to build the dates for the calendar
			eval {
				$start = $self->get_time( $data->{when} );

				# Crudely determine if this is an all-day event
				# (Assume that midnight events are all day)
				$all = $start->hour() == 0 && $start->minute() == 0;
			};

			if ( my $err = $@ ) {
				$self->re( 1, $msg, "Problem with date format. See: http://j.mp/e7V35j" );
				return;
			}

			# The date was built, now build the calendar entry
			if ( defined $cal ) {
				eval {
					my $entry = Net::Google::Calendar::Entry->new();
					$entry->title( $data->{name} );
					$entry->content( $msg->{body} );
					$entry->location( $self->find_place( $data ) );
					$entry->transparency( "transparent" );
					$entry->visibility( "public" );

					# All events are two hours long by default
					$entry->when( $start, $start + DateTime::Duration->new( hours => 2 ), $all );

					# The author is just a fake person
					my $author = Net::Google::Calendar::Person->new();
					$author->name( $ini->{irc}{name} );
					$author->email( $ini->{google}{email} );
					$entry->author( $author );

					$entry = $cal->add_entry( $entry );

					# Save the ID generated by Google Calendar so we can remove it later
					$data->{id} = $entry->id();
				};

				if ( my $err = $@ ) {
					$self->re( 1, $msg, "Problem saving calendar entry, please try again later." );
					return;
				}
			}

			# The calendar was saved so save the data as well
			push( @events, $data );

			# Make sure all the events are saved in order
			@events = sort { $a->{when} <=> $b->{when} } @events;

			# Update the topic
			$self->update_topic();

    } else {
			return $self->help();
		}
	}

	# Return undefined to not display a response
	return;
}

# Find an associated place in the DB
sub find_place {
	my $self = shift;
	my $event = shift;
	my $cur = $event->{place} || $event->{name};

	foreach my $place ( sort keys %places ) {
		# See if the place matches the key
		if ( $cur =~ /$place/i ) {
			return $places{ $place };
		}
	}

	return $cur;
}

# Routine for saving the place list to a file
sub save_places {
	my $self = shift;
	my $msg = shift;

	print STDERR "Saving places...\n";

	# Encode all the places data
	my $json = encode_json( \%places );

	open( JSON, '>' . $ini->{places}{backup} );
	print JSON $json;
	close( JSON );

	# Provide an optional JSONP file
	if ( defined $ini->{places}{backup_jsonp} ) {
		open( JSON, '>' . $ini->{places}{backup_jsonp} );
		print JSON "$ini->{config}{backup_jsonp_fn}($json);";
		close( JSON );
	}

	# Notify the user of the save
	$self->re( 0, $msg, "Place list updated." );
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

	# Get the current day of the year for comparison
	my $now = $self->get_time( time() );
	my $cur = $now->doy();
	my $remove = 0;

	# Go through all the events
	for ( my $i = 0; $i <= $#events; $i++ ) {
		# Get their day of the year
		my $when = $self->get_time( $events[$i]->{when} );
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
	my $now = $self->get_time( time() );
	my $cur = $now->doy();
	my $prev = $now;
	my $disp = "";
	my $later = 0;

	# Go through all the events
	foreach my $event ( @events ) {
		# Get their day of the year
		my $when = $self->get_time( $event->{when} );
		my $day = $when->doy();

		# Make sure the date offset is handled correctly
		if ( $day < $cur && $event->{when} > time() ) {
			$day += 365;
		}

		# Only care about days within the next week
		if ( $day <= $cur + 7 ) {
			if ( $disp ne "$day" ) {
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
			# Display the month/day at the end of the list
			if ( $later && $day != $disp ) {
				$topic .= " " . $prev->strftime("%b %e");
			}

			# Handle the separation of items in the topic
			$topic .= ($topic eq "" ? "" : !$later ? " | Later: " : 
				$day != $disp ? ", " : " & ");

			# Only display the name of the event and date (no location or time)
			$topic .= $event->{name};

			$later = 1;
		}

		$disp = $day;
		$prev = $when;
	}

	# Display the month/day at the end of the list
	if ( $later ) {
		$topic .= " " . $prev->strftime("%b %e");
	}

	$topic =~ s/ +/ /g;

	# If no events, add a Richard-ism
	if ( $topic eq "" ) {
		$topic = "Embrace death.";
	}

	# A way to get at the current topic
	if ( defined $cur_topic && $cur_topic eq "1" ) {
		return $topic;
	}

	# The topic is identical to what's there, don't update
	if ( defined $cur_topic && $topic eq $cur_topic ) {
		return;
	}

	print STDERR "Updating: $topic\n";

	# Backup the topic data
	my $json = encode_json( \@events );

	open( JSON, '>' . $ini->{config}{backup} );
	print JSON $json;
	close( JSON );

	# Provide an optional JSONP file
	if ( defined $ini->{config}{backup_jsonp} ) {
		open( JSON, '>' . $ini->{config}{backup_jsonp} );
		print JSON "$ini->{config}{backup_jsonp_fn}($json);";
		close( JSON );
	}

	# Update the topic in the channel
	$self->{IRCOBJ}->yield(
		sl_prioritized => 30,
		"TOPIC #" . $ini->{irc}{channel} . " :$topic" );

	# Post the topic to PingFM
	if ( defined $ping ) {
		eval {
			$ping->post( $topic );
		};

		if ( my $err = $@ ) {
			print STDERR "ERROR: $err\n";
		}
	}
}

sub parse_date {
	my ( $self, $date ) = @_;

	my $time = parsedate( $date,
		ZONE => $ini->{config}{timezone_short},
		PREFER_FUTURE => 1
	);

	return $time;
}

sub get_time {
	my ( $self, $date ) = @_;

	return DateTime->from_epoch(
		epoch => $date,
		time_zone => $ini->{config}{timezone}
	);
}
