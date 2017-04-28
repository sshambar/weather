#!/usr/bin/perl

use strict;

use Time::Local;
use IO::Select;
use IO::Handle;

my $user = "mshambar";
my $password = "brandy8112";

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


my %dash_value = (
		  'tempout' => 32767,
		  'hightempout' => -32768,
		  'lowtempout' => 32767,
		  'rainclicks' => 0,
		  'highrainrate' => 0,
		  'barometer' => 0,
		  'solarradiation' => 32767,
		  'windsamples' => 0,
		  'tempin' => 32767,
		  'humin' => 255,
		  'humout' => 255,
		  'avgwindspeed' => 255,
		  'highwindspeed' => 0,
		  'highwindspeeddir' => 255,
		  'prevailingwinddir' => 255,
		  'uv' => 255,
		  'et' => 0, 
		  'highsolarradiation' => 32767,
		  'highuv' => 255,
		  'forecastrule' => 193);

my %value;

my $max_nof_sample_per_min = 23;
my $packet_size = 52;
my $rain_in_per_click = 0.01;
my $et_in_per_click = 0.001;

my $year = shift @ARGV or &usage();
my $month = shift @ARGV or &usage();
my $day = shift @ARGV or &usage();
my $hour = shift @ARGV or &usage();
my $minute = shift @ARGV or &usage();

my $timestamp = $day + $month*32 + ($year - 2000)*512;
$timestamp = $timestamp * 65536;
$timestamp = $timestamp + (100 * $hour) + $minute;

open (WL, "wget -O - \"http://www.weatherlink.com/webdl.php?timestamp=$timestamp&user=$user&pass=$password&action=headers\" 2> /dev/null |");
while (<WL>) {
	if (/^Records=(\d+)/) { 
		my $nofRecords = $1;
		print "nofRecords $nofRecords\n";
	}
}
close(WL);

open (WL, "wget -O - \"http://www.weatherlink.com/webdl.php?timestamp=$timestamp&user=$user&pass=$password&action=data\" 2> /dev/null |");
	
my $file = new IO::Handle;
$file->fdopen(fileno(WL),"r");
&getDMPPage();        
$file->close;
close(WL);

exit(0);

sub getDMPPage {
	my ($c, $in);
	while($c = $file->read($in,$packet_size)) {
		&readBlock($in);
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
	$value{'date'} = "$StartYear-$StartMonth-$StartDay";
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

	foreach my $key (keys %dash_value) {
		$value{$key} = "--" if ($value{$key} == $dash_value{$key});
	}
    
	print $value{'date'},"\t";
	print $value{'time'},"\t";	
	print sprintf("%.1f",&HGtoPA(&INtoMM($value{'barometer'}/100000))),"\t";
	print sprintf("%.1f",&FtoC($value{'tempin'}/10)),"\t";
	print $value{'humin'},"\t";
	print sprintf("%.1f",&FtoC($value{'tempout'}/10)),"\t";
	print $value{'humout'},"\t";
	print $value{'windsamples'},"\t";
	print sprintf("%.1f",&MPHtoKMH($value{'avgwindspeed'})),"\t";
	print $direction_value{$value{'prevailingwinddir'}},"\t";
	print sprintf("%.1f",&MPHtoKMH($value{'highwindspeed'})),"\t";
	print $direction_value{$value{'highwindspeeddir'}},"\t";
	print sprintf("%.1f",&INtoMM($value{'highrainrate'} * $rain_in_per_click)),"\t";
	print sprintf("%.1f",&INtoMM($value{'rainclicks'} * $rain_in_per_click)),"\t";
#	print $value{'uv'},"\t";
	print sprintf("%.1f",&INtoMM($value{'et'} * $et_in_per_click)),"\t"; 
	print $value{'solarradiation'},"\t";
	print $value{'highsolarradiation'},"\t";
#	print $value{'highuv'},"\t"; 
	print $value{'forecastrule'},"\n";
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

sub FtoC {
	my $F = shift @_;
	my $C = (5.0/9.0)*($F-32);
	return $C;
}

sub INtoMM {
	my $IN = shift @_;
	my $MM =$IN * 25.4;
	return $MM;
}

sub MPHtoKMH {
	my $MPH = shift @_;
	my $KMH = $MPH * 1.609344;
	return $KMH;
}


sub HGtoPA {
	my $HG = shift @_;
	my $PA = $HG * 133.322;
	return $PA;
}

sub usage {
    die ("Usage: decodeWL.pl year month day hour minute\n"); 
}
