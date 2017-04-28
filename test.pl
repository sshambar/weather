#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(switch say);

my %value;
$value{'test'} = 'value';
sub vardump {
    foreach my $key (keys $_[0]) {
	print "$key = $_[0]->{$key}\n";
    }
}
vardump(\%value);
