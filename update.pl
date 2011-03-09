#!/usr/bin/perl
# Trim old events that should no longer be displayed.
# Written by John Resig
#   http://ejohn.org/

use 5.010;
use strict;
use warnings;

use WTPA;
use Config::Abstract::Ini;

our $ini = (new Config::Abstract::Ini( 'config.ini' ))->get_all_settings;

utilInit( $ini );

trimEvent();