package WTPA;

use 5.010;
use strict;
use warnings;

# Includes, please install all ahead of time
# All can be found on CPAN
use JSON;
use DateTime;
use Net::PingFM;
use Time::ParseDate;
use WWW::Shorten::Bitly;
use Net::Google::Calendar;
use Config::Abstract::Ini;
use base 'Exporter';

our @EXPORT = qw( utilInit calConnect pingConnect events places
	loadBackup saveBackup loadPlaces savePlaces
	addEvent updateEvent cancelEvent trimEvent
	addPlace updatePlace findPlace placeURL
	getTopic getToday
	getTime parseDate );

our $VERSION = '0.1';

our $cal;
our $ping;
our $ini;
our $lastPull;

our @events;
our %places;

sub utilInit {
	$lastPull = time();
	$ini = shift;
	
	loadBackup();
	loadPlaces();
}

sub calConnect {
	# Connect to Google Calendar
	if ( !(defined $cal) && defined $ini->{google}{user} ) {
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
}

sub pingConnect {
	# Connect to PingFM
	if ( !(defined $ping) && defined $ini->{ping}{user} ) {
		$ping = Net::PingFM->new(
			user_key => $ini->{ping}{user},
			api_key => $ini->{ping}{key}
		);

		$ping->user_validate or die "Login failed.";
	}
}

# Load the old data from the backup file
sub loadBackup {
	open( JSON, $ini->{config}{backup} );
	my $json = <JSON>;
	@events = @{$json ne "" ? decode_json( $json ) : []};
	close( JSON );
}

sub saveBackup {
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
	
	pingConnect();
	
	# Post the topic to PingFM
	if ( defined $ping ) {
		eval {
			$ping->post( getTopic() );
		};

		if ( my $err = $@ ) {
			return "ERROR: $err\n";
		}
	}
}

# Load in all the addresses being used
sub loadPlaces {
	open( JSON, $ini->{places}{backup} );
	my $json = <JSON>;
	%places = %{$json ne "" ? decode_json( $json ) : {}};
	close( JSON );
}

sub savePlaces {
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
}

sub addEvent {
	my $data = shift;
	my $start;
	my $all;
	
	$data->{when} = parseDate( $data->{when} );

	# We need to build the dates for the calendar
	eval {
		$start = getTime( $data->{when} );

		# Crudely determine if this is an all-day event
		# (Assume that midnight events are all day)
		$all = $start->hour() == 0 && $start->minute() == 0;
	};

	if ( my $err = $@ ) {
		return "Problem with date format. See: http://j.mp/e7V35j";
	}
	
	calConnect();

	# The date was built, now build the calendar entry
	if ( defined $cal ) {
		eval {
			my $entry = Net::Google::Calendar::Entry->new();
			$entry->title( $data->{name} );
			$entry->content( "" );
			$entry->location( findPlace( $data ) );
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
			return "Problem saving calendar entry, please try again later.";
		}
	}

	# The calendar was saved so save the data as well
	push( @events, $data );

	# Make sure all the events are saved in order
	@events = sort { $a->{when} <=> $b->{when} } @events;
	
	return saveBackup();
}

sub updateEvent {
	my ( $name, $desc, $data ) = @_;
	
	my $start;
	my $all;
	
	$data->{when} = parseDate( $data->{when} );

	# We need to build the dates for the calendar
	eval {
		$start = getTime( $data->{when} );

		# Crudely determine if this is an all-day event
		# (Assume that midnight events are all day)
		$all = $start->hour() == 0 && $start->minute() == 0;
	};

	if ( my $err = $@ ) {
		return "Problem with date format. See: http://j.mp/e7V35j";
	}

	# Loop through all the events
	for ( my $i = 0; $i <= $#events; $i++ ) {
		my $event = $events[$i];

		# And look for one whose name matches
		if ( $event->{name} =~ /$name/i ) {
			print STDERR "Updating $event->{name}\n";
			
			calConnect();

			# Be sure to update the associated Google Calendar event
			if ( defined $cal ) {
				eval {
					foreach my $item ( $cal->get_events() ) {
						if ( $item->id() eq $event->{id} ) {
							# Update fields in calendar
							$item->title( $data->{name} );
							$item->content( $desc );
							$item->location( findPlace( $data ) );

							# All events are two hours long by default
							$item->when( $start, $start + DateTime::Duration->new( hours => 2 ), $all );

							# Update the entry on the server
							$cal->update_entry( $item );
						}
					}
				};

				if ( my $err = $@ ) {
					return "Problem finding associated calendar entry.";
				}
			}

			# Update the details of the event
			$event->{name} = $data->{name};
			$event->{place} = $data->{place};
			$event->{when} = $data->{when};
			
			# Only update the first found event
			return saveBackup();
		}
	}	
}

sub cancelEvent {
	my $name = shift;

	# Loop through all the events
	for ( my $i = 0; $i <= $#events; $i++ ) {
		# And look for one whose name matches
		if ( $events[$i]->{name} =~ /$name/i ) {
			print STDERR "Cancelling $events[$i]->{name}\n";
			
			calConnect();

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
					return "Problem finding associated calendar entry.";
				}
			}

			# Remove the event
			splice( @events, $i, 1 );
			
			# Only remove the first found event
			return saveBackup();
		}
	}
}

sub trimEvent {
	my $remove = 0;
	my $mtime = (stat( $ini->{config}{backup} ))[9];

	# Check to see if the data was updated via the web interface
	if ( $lastPull && $mtime > $lastPull ) {
		loadBackup();
		$remove = 1;
	}

	$lastPull = $mtime;

	# Get the current day of the year for comparison
	my $now = getTime( time() );
	my $cur = $now->doy();

	# Go through all the events
	for ( my $i = 0; $i <= $#events; $i++ ) {
		# Get their day of the year
		my $when = getTime( $events[$i]->{when} );
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
	
	return $remove;
}

sub addPlace {
	my ( $new_place, $new_address ) = @_;

	$places{ $new_place } = $new_address;
	
	savePlaces();
}

sub updatePlace {
	my ( $match, $new_place, $new_address ) = @_;

	# Look through places, finding the first one to replace
	foreach my $place ( sort keys %places ) {
		if ( $place =~ /$match/i ) {
			delete $places{ $place };

			if ( $new_place ) {
				$places{ $new_place } = $new_address;
			}
		}

		last;
	}
	
	savePlaces();
}

# Find an associated place in the DB
sub findPlace {
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

sub placeURL {
	my $place = shift;
	my $event = shift;
	
	if ( $place ne $event->{name} &&
		(!(defined $event->{place}) || $place ne $event->{place}) ) {
		 	return "http://maps.google.com/maps?q=$place";
	}
	
	return "";
}

sub getTopic {
	my $topic = "";

	# Get the current day of the year
	my $now = getTime( time() );
	my $cur = $now->doy();
	my $prev = $now;
	my $disp = "";

	# Go through all the events
	foreach my $event ( @events ) {
		# Get their day of the year
		my $when = getTime( $event->{when} );
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

		# Items further in the future are removed
		}

		$disp = $day;
		$prev = $when;
	}

	$topic =~ s/ +/ /g;

	# If no events, add a Richard-ism
	if ( $topic eq "" ) {
		$topic = "Embrace death.";
	}

	return $topic;	
}

sub getToday {
	my $re = "";
	
	# Get the current day of the year
	my $now = getTime( time() );
	my $cur = $now->doy();

	# Go through all the events
	foreach my $event ( @events ) {
		# Get their day of the year
		my $when = getTime( $event->{when} );
		my $day = $when->doy();

		if ( $day == $cur ) {
			my $place = findPlace( $event );
			my $url = placeURL( $place, $event );

			if ( defined $ini->{bitly}{user} && $url ) {
				$url = makeashorterlink( $url,
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

	return $re || "No party today!";	
}

sub getTime {
	my ( $date ) = @_;

	return DateTime->from_epoch(
		epoch => $date,
		time_zone => $ini->{config}{timezone}
	);
}

sub parseDate {
	my ( $date ) = @_;

	my $time = parsedate( $date,
		ZONE => $ini->{config}{timezone_short},
		PREFER_FUTURE => 1
	);

	return $time;
}

1;
