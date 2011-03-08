#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use CGI;

my $cgi = new CGI();
my $index = join( "", <DATA> );

if ( $cgi->param('action') eq 'add' ) {
	
} else {
	
}

print "Content-type: text/html\n\n";
print $index;

__DATA__
<!DOCTYPE html>
<html>
<head>
	<title>Update WTPA</title>
</head>
<body>
	<h1>Where is the Party at?</h1>
	<p>Today: TODAY</p>
	<p>Upcoming: UPCOMING</p>
	<h2>Add New Event:</h2>
	<form action="" method="POST">
		<input type="hidden" name="action" value="add"/>
		Name: <input type="text" name="name"/><br/>
		Location: <input type="text" name="location"/><br/>
		Date: <input type="text" name="date" value="01/01/2011"/><br/>
		Time: <input type="text" name="time" value="7:00"/> <select name="ampm">
		<option>pm</option><option>am</option></select><br/>
		<input type="submit" value="Add Event"/>
	</form>
</body>
</html>