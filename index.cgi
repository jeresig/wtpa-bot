#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use CGI;

our @events;
our %places;

my $cgi = new CGI();
my $action = $cgi->param('action') || "";
my $index = join( "", <DATA> );

require "utils.pl";

our $ini = (new Config::Abstract::Ini( 'config.ini' ))->get_all_settings;

init();

if ( $action eq 'add' ) {
	my $err = addEvent({
		name => $cgi->param('name'),
		place => $cgi->param('place'),
		when => $cgi->param('date') . ' ' . $cgi->param('time') . $cgi->param('ampm')
	}) || "Event saved.";
	
	$index =~ s/MSG/$err/g;

} elsif ( $action eq 'update' ) {
	my $err = updateEvent($cgi->param('old'), "", {
		name => $cgi->param('name'),
		place => $cgi->param('place'),
		when => $cgi->param('date') . ' ' . $cgi->param('time') . $cgi->param('ampm')
	}) || "Event updated.";

	$index =~ s/MSG/$err/g;

} elsif ( $action eq 'cancel' ) {
	my $err = cancelEvent($cgi->param('old')) || "Event cancelled.";
	$index =~ s/MSG/$err/g;

} elsif ( $action eq 'addplace' ) {
	addPlace( $cgi->param('name'), $cgi->param('address') );
	$index =~ s/MSG/Place added./g;

} elsif ( $action eq 'updateplace' ) {
	updatePlace( $cgi->param('old'), $cgi->param('name'), $cgi->param('address') );
	$index =~ s/MSG/Place updated./g;
}

my $toUpdate = "";

foreach my $event ( @events ) {
	my $when = getTime( $event->{when} );
	my $name = $event->{name};
	my $place = $event->{place} || "";
	my $date = $when->strftime("%D");
	my $time = $when->strftime("%I:%M");
	my $ampm = $when->strftime("%P");
	my $nice_date = $when->strftime("%b %e");
	my $nice_time = ($when->hour > 0 ? " " . $when->strftime(
		# Don't display the minutes when they're :00
		$when->minute > 0 ? "%l:%M%P" : "%l%P" ) : "");
	my $nice_place = $place;
	my $dbPlace = placeURL( findPlace( $event ), $event );
	my $namePlace = $nice_place ? "$event->{name} @ $nice_place" : $event->{name};
	
	$namePlace = $dbPlace ?
		"<a href='$dbPlace'>$namePlace</a>" :
		$namePlace;
	
	$name =~ s/"/\\"/g;
	$place =~ s/"/\\"/g;
	
	# Display the name and location of the event
	$toUpdate .= qq~<li><span class="date">$nice_date $nice_time:</span> $namePlace
		<span class='buttons'>
			<input type='button' value='Update' class="update"/>
			<form action="" method="POST" class="cance">
				<input type="hidden" name="action" value="cancel"/>
				<input type="hidden" name="old" value="' + data.name + '"/>
				<input type="submit" value="Cancel"/>
			</form>
		</span>
		<form action="" method="POST" class="update">
			<input type="hidden" name="action" value="update"/>
			<input type="hidden" name="old" value="$name"/>
			<label for="name">Name:</label><input type="text" name="name" value="$name"/><br/>
			<label for="place">Place:</label><input type="text" name="place" value="$place"/><br/>
			<label for="date">Date:</label><input type="text" name="date" value="$date"/><br/>
			<label for="time">Time:</label><input type="text" name="time" value="$time"/> <select name="ampm">
			<option>$ampm</option><option>pm</option><option>am</option></select><br/>
			<label></label><input type="submit" value="Update Event"/> <input type="reset" value="Cancel"/>
		</form>
	</li>~;
}

my $placeList = "";

foreach my $place ( sort { lc($a) cmp lc($b) } keys %places ) {
	$placeList .= qq~<li><form action="" method="POST">
		<input type="hidden" name="action" value="updateplace"/>
		<input type="hidden" name="old" value="$place"/>
		<label for="name">Name:</label><input type="text" name="name" value="$place"/>
		<label for="address">Address:</label><input type="text" name="address" value="$places{$place}"/>
		<input type="submit" value="Update"/>
	</form></li>~;
}

$index =~ s/UPCOMING/$toUpdate/g;
$index =~ s/PLACES/$placeList/g;
$index =~ s/MSG//g;

print "Content-type: text/html\n\n";
print $index;

__DATA__
<!DOCTYPE html>
<html>
<head>
	<meta name="ROBOTS" content="NOINDEX, NOFOLLOW"/>
	<title>Update WTPA</title>
	<link rel="stylesheet" href="main.css"/>
	<script src="http://code.jquery.com/jquery.js"></script>
	<script src="main.js"></script>
</head>
<body>
	<h1>Where is the Party at?</h1>
	<p style="color:red;">MSG</p>
	<h2>Events:</h2>
	<ul id="upcoming">UPCOMING</ul>
	<h2>Add New Event:</h2>
	<form action="" method="POST">
		<input type="hidden" name="action" value="add"/>
		<label for="name">Name:</label><input type="text" name="name"/><br/>
		<label for="place">Place:</label><input type="text" name="place"/><br/>
		<label for="date">Date:</label><input type="text" name="date" value="01/01/2011"/><br/>
		<label for="time">Time:</label><input type="text" name="time" value="7:00"/> <select name="ampm">
		<option>pm</option><option>am</option></select><br/>
		<label></label><input type="submit" value="Add Event"/>
	</form>
	<h2>Places:</h2>
	<ul id="places">PLACES</ul>
	<h2>Add New Place:</h2>
	<form action="" method="POST">
		<input type="hidden" name="action" value="addplace"/>
		<label for="name">Name:</label><input type="text" name="name"/>
		<label for="address">Address:</label><input type="text" name="address"/>
		<input type="submit" value="Add Place"/>
	</form>
</body>
</html>
