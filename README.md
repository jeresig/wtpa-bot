A bot for syncing IRC topic changes with Google Calendar, Twitter, and Facebook.
  by John Resig: http://ejohn.org/

# How to use

You can converse with the bot either through messaging in a channel or my sending it a direct message. If you're working by direct message and you wish to see the current topic just send the bot the following to see it:

    wtpa topic

Note that all dates follow the date conventions specified here:
http://j.mp/e7V35j

This documentation assumes that the name of the bot is 'wtpa'.

## What's Happening?

To find out what's happening just send the bot a message with no text, for example:

    wtpa

Will cause it to respond with a list of everything that's happening today along with locations and maps to get to find the locations.

## Creating an Event

Make an event today, location extracted from name:

    wtpa Tam Trivia @ 8:30pm

(Note: Be sure to specify pm! If left off, am will be assumed.)

Makes an event tomorrow, location extracted from name:

    wtpa Tam Trivia @ Tomorrow 8:30pm

If you have an event far in the future you can specify the date using a normal date-like syntax:

    wtpa Tam Trivia @ March 2 8:30pm
    wtpa Tam Trivia @ 3/2/11 8:30pm

Make an event today, at 8pm, at a specific location (Note the use of a comma!):

    wtpa Party @ John's, 8pm

Make an event Sunday at a specific location:

    wtpa Skiing @ Loon, Sunday 6am

Make an all day event:

    wtpa John's Birthday @ Sunday 0:00am

## Updating an Event

To update an event you must search for the event by name. You can use any part of the name to match. For example to match the event "Tam Trivia" you could use "tam" or "Tam" or "trivia" or "Tam Trivia". The first matching event will be updated.

Change the time of Trivia to earlier:

    wtpa update trivia: Tam Trivia @ 8pm

Note the colon separating the search term from the updated event. The event update syntax is identical to the event creation syntax.

## Canceling an Event

This works just like updating an event (same syntax). Only the first matched event is cancelled.

Canceling trivia:

    wtpa cancel trivia

## Getting the List of Locations

To see the current list of all known locations just use:

    wtpa places

## Adding a New Location

You can add new locations to the list. The names of the locations are in the format of a regular expression and can contain multiple matches.

Add a location for Bella Luna:

    wtpa places add bella|luna 284 Amory St 02130

(Note that the name of the place is split by a | (regex syntax), followed by a space, and then the full address.)

## Update an Existing Location

This update process works the same as updating an existing event.

To update the Bella Luna entry to include 'milky' (for Milky Way) you could do:

    wtpa places update luna: bella|luna|milky 284 Amory St 02130
