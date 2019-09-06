#!/usr/bin/perl

use strict;
use warnings;
use feature qw(say);

use DBI;
use Time::Local;
use IO::Select;
use IO::Handle;
use Pod::Usage;
use Getopt::Long qw(:config no_ignore_case bundling auto_help);

# import.conf entries:
#  db = <dbname>
#  db.username = <db user>
#  db.password = <db password>
#  db.source = <source name, see weather_sources>
#  username = <weatherlink username>
#  password  = <weatherlink password>

my $def_config = "/etc/weather/import.conf";

my $config = $def_config;
my $debug = 0;
my $test = 0;
my $man = ''; ## man page at end of file

GetOptions ('config|f=s' => \$config,
	    'debug|d+' => \$debug,
	    'test|t+' => \$test,
	    'man' => \$man)
    or pod2usage();

pod2usage(-verbose => 2) if $man;

my %options;
my @cparams = qw(username password timezone db db.username db.password db.source);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime;
my @curtime = gmtime;
my $CurrentYear = $curtime[5] + 1900;

if ($debug) { 
    say "Configfile is '$config'"; 
}

open(CONFIG, $config) or die "Unable to read config $config: $!\n";
while (<CONFIG>) {
    next if /^\s*#/;
    next if /^\s*$/;
    if ($_ =~ /^\s*(\S+)\s*=\s*(\S+)\s*$/) {
	my ($key, $val) = ($1, $2);
	die "Unknown config key: '$key'\n" if not grep { $_ eq $key } @cparams;
	if ($debug) { say "  $key = $val"; }
	$options{$key} = $val;
    } else {
	die "Invalid config entry: $_\n";
    }
}
close(CONFIG);
foreach (@cparams) {
    die "Config $config missing $_ entry\n" if not defined($options{$_});
#    say "'$_'='$options{$_}'";
}

my %direction_value = (
		        0 => "N",
		        1 => "NNE",
		        2 => "NE",
		        3 => "ENE",
		        4 => "E",
		        5 => "ESE", 
		        6 => "SE",
		        7 => "SSE",
		        8 => "S",
		        9 => "SSW",
		        10 => "SW",
		        11 => "WSW",
		        12 => "W",
		        13 => "WNW",
		        14 => "NW",
		       15 => "NNW");


my %value;

my $max_nof_sample_per_min = 23;
my $packet_size = 52;
my $rain_in_per_click = 0.01;
my $et_in_per_click = 0.001;
my $timestamp = 0;

if ($debug) { say "Connection to mysql table $options{'db'}"; }

my $dbh = DBI->connect("DBI:mysql:$options{'db'}", $options{'db.username'}, $options{'db.password'}, { PrintError => 0, AutoCommit => 1 })
    or die $DBI::errstr;

my $result = $dbh->selectrow_hashref('SELECT max(s.time_observed) start
				     FROM weather_samples s, weather_sources r
				     WHERE s.source_id = r.id
				     AND r.name = ?', undef, 
				     $options{'db.source'})
    or die $dbh->errstr;

if (defined($result->{'start'})) {

    if ($debug) { say "Newest sample timestamp: $result->{'start'}"; }

    my ($year, $month, $day, $hour, $minute, $second) =
	$result->{'start'} =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;

    $timestamp = $day + $month*32 + ($year - 2000)*512;
    $timestamp = $timestamp * 65536;
    $timestamp = $timestamp + (100 * $hour) + $minute;
}

if ($debug) { say "Getting URL: http://weatherlink.com/webdl.php?timestamp=$timestamp&user=$options{'username'}&pass=$options{'password'}&action=headers"; }

my $nofRecords = 0;
open (WL, "wget -O - \"http://weatherlink.com/webdl.php?timestamp=$timestamp&user=$options{'username'}&pass=$options{'password'}&action=headers\" 2> /dev/null |");
while (<WL>) {
    if (/^Records=(\d+)/) { $nofRecords = $1; }
}
close(WL);

if ($debug) { say "New records: $nofRecords"; }

if (! $nofRecords) { exit 0; }

if ($debug) { say "Getting URL: http://weatherlink.com/webdl.php?timestamp=$timestamp&user=$options{'username'}&pass=$options{'password'}&action=data"; }

open (WL, "wget -O - \"http://weatherlink.com/webdl.php?timestamp=$timestamp&user=$options{'username'}&pass=$options{'password'}&action=data\" 2> /dev/null |");
	
my $file = new IO::Handle;
$file->fdopen(fileno(WL),"r");
&getDMPPage();        
$file->close;
close(WL);

$dbh->disconnect();

exit(0);

sub getDMPPage {
	my ($c, $in);
	while($c = $file->read($in,$packet_size)) {
	    &readBlock($in);
	    return if $test;
	}	
}
    

sub readBlock {
   
	my $in = shift @_; 
	my @packet=split(//,$in);
    
	my $StartDatetmp = hex scalar reverse unpack('h*', join('',$packet[0],$packet[1]));
	my $StartDay = $StartDatetmp & 0x1f;
	$StartDatetmp = $StartDatetmp >> 5;
	my $StartMonth = $StartDatetmp & 0x0f;
	$StartDatetmp = $StartDatetmp >> 4;
	my $StartYear = $StartDatetmp;
	$StartYear = 2000 + $StartYear;
	$value{'time'} = &dodate(unpack('S*', join('',$packet[2],$packet[3])));
	$value{'tempout'} = unpack('S*', join('',$packet[4],$packet[5]));
	$value{'hightempout'} = unpack('S*', join('',$packet[6],$packet[7]));
	$value{'lowtempout'} = unpack('S*', join('',$packet[8],$packet[9]));
	$value{'rainclicks'} = unpack('S*', join('',$packet[10],$packet[11]));
	$value{'highrainrate'} = unpack('S*', join('',$packet[12],$packet[13]));
	$value{'barometer'} = unpack('S*', join('',$packet[14],$packet[15]));
	$value{'solarradiation'} = unpack('S*', join('',$packet[16],$packet[17]));
	$value{'windsamples'} = unpack('S*', join('',$packet[18],$packet[19]));
	$value{'tempin'} = unpack('S*', join('',$packet[20],$packet[21]));
	$value{'humin'} = unpack('C*', $packet[22]);
	$value{'humout'} = unpack('C*', $packet[23]);
	$value{'avgwindspeed'} = unpack('C*', $packet[24]);
	$value{'highwindspeed'} = unpack('C*', $packet[25]);
	$value{'highwindspeeddir'} = unpack('C*', $packet[26]);
	$value{'prevailingwinddir'} = unpack('C*', $packet[27]);
	$value{'uv'} = unpack('C*', $packet[28]);
	$value{'et'} = unpack('C*', $packet[29]);
	$value{'highsolarradiation'} = unpack('S*', join('',$packet[30],$packet[31]));
	$value{'highuv'} = unpack('C*', $packet[32]);
	$value{'forecastrule'} = unpack('C*', $packet[33]);
	$value{'rx'} = $value{'windsamples'} / $max_nof_sample_per_min * 100;
	# a few sanity checks
	if ($StartYear > $CurrentYear) {
	    # generally, this tells us there's no data
	    #say "Invalid StartYear > $CurrentYear: $StartYear";
	    return;
	}
	if ($value{'tempin'} > 1500) {
	    say "Invalid tempin > 1500: $value{'tempin'}";
	    return;
	}
	if ($value{'tempout'} > 1500) {
	    say "Invalid tempout > 1500: $value{'tempout'}";
	    return;
	}
	if ($value{'avgwindspeed'} > 100) {
	    say "Invalid avgwindspeed > 100: $value{'avgwindspeed'}";
	    return;
	}

	$value{'winddir'} = $direction_value{$value{'prevailingwinddir'}};
	$value{'winddir'} = '' if not $value{'winddir'};
	$value{'hiwinddir'} = $direction_value{$value{'highwindspeeddir'}};
	$value{'hiwinddir'} = '' if not $value{'hiwinddir'};

	$value{'date'} = "$StartYear-$StartMonth-$StartDay $value{'time'}";
	if ($debug) {
	    say "Values parsed: ";
	    say vardump(\%value);
	}
	return if $test;
	$dbh->do('INSERT INTO weather_samples (source_id, time_observed,
		    time_utc, barometer, temp_in, humid_in, temp_out,
		    high_temp_out, low_temp_out, humid_out, wind_samples,
		    wind_speed, wind_dir, high_wind_speed, high_wind_dir,
		    rain, high_rain)
		  SELECT r.id, ?, convert_tz(?, ?, "+00:00"),
		    ?, ?, ?, ?, ?, ?, ?, ?, ?, w.id, ?, hw.id, ?, ?
		  FROM weather_sources r, weather_windmap w, 
		    weather_windmap hw
		  WHERE r.name = ? AND w.direction = ? AND hw.direction = ?',
		 undef,
		 ($value{'date'}, $value{'date'}, $options{'timezone'},
		  numfmt($value{'barometer'}/1000),
		  numfmt($value{'tempin'}/10), numfmt($value{'humin'}),
		  numfmt($value{'tempout'}/10),
		  numfmt($value{'hightempout'}/10),
		  numfmt($value{'lowtempout'}/10), numfmt($value{'humout'}),
		  $value{'windsamples'}, numfmt($value{'avgwindspeed'}),
		  numfmt($value{'highwindspeed'}),
		  numfmt($value{'rainclicks'} * $rain_in_per_click),
		  numfmt($value{'highrainrate'} * $rain_in_per_click),
		  $options{'db.source'}, $value{'winddir'},
		  $value{'hiwinddir'}))
	    or (say vardump(\%value) and die $dbh->errstr);
}

sub vardump {
    foreach my $key (keys %{ $_[0] }) {
	print "$key = $_[0]->{$key}\n";
    }
}

sub numfmt {
    return sprintf("%.2f", $_[0]);
}

sub dodate {
	my $d = shift @_;
	my $date;

	if( $d =~ /\d\d\d\d\d/ ){ $date = "\x00" }
	elsif( $d =~ /(\d\d)(\d\d)/ ){ $date = "${1}:${2}"; }
	elsif( $d =~ /(\d)(\d\d)/ ){ $date = "0${1}:${2}"; }
	elsif ($d =~ /(\d\d)/ ) {$date = "00:${1}";}
	elsif ($d =~ /(\d)/ ) {$date = "00:0${1}";}
	return("$date");
}


__END__

=head1 NAME

weatherlink.pl - WeatherLink Data Import

=head1 SYNOPSIS

weatherlink.pl [options]

 Options:
    -?, --help    brief help message
    --man         full documentation
    -d, --debug   increase debug level
    -t, --test    don't save to database
    -f, --config  specify config file (default: "/etc/weather/import.conf")
    
=head1 DESCRIPTION

This program will connect to the Davis web servers and download
the latest weather data, parse it, and import it into the database
specified in the config file.

=cut
