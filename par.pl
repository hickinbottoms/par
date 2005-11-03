#!/usr/bin/perl

use warnings;
use strict;
use POSIX qw(strftime tmpnam);
use File::Path;
use Mail::Sendmail;

sub download_and_convert($$$$$$$);

# Usage
if (scalar @ARGV != 5)
{
	print STDERR "Usage: par.pl <stream> <basedir> <artist> <Programme Name> <min_length_megs>\n";
	exit 1;
}

my $argc = 0;
my $stream = $ARGV[$argc++];
my $basedir = $ARGV[$argc++];
my $artist = $ARGV[$argc++];
my $basename = $ARGV[$argc++];
my $min_length = $ARGV[$argc++];

my $max_attempts = 5;
my $retry_pause = 600;

# Crack the current time.
my @time_now = gmtime;
my $date = strftime "%G-%m-%d", @time_now;
my $week = strftime "%U", @time_now;
my $year = strftime "%G", @time_now;

# Make the output directory (if necessary)
( -d "$basedir" ) or mkpath($basedir)
	or die "par.pl: Can't make output directory $basedir";

# Filenames
my $wav_filename = tmpnam();
my $mp3_filename = "$basedir/$date $basename.mp3";

# ID3.x tags
my $album = "$basename";
my $title = "$date $basename";

print "par.pl: Recording to $mp3_filename\n";

# Try a few times to download and convert - sometimes the download is
# truncated early.
my $size_ok = 0;
my $mp3_length = 0;
for (my $attempt = 1; ($attempt <= $max_attempts) && !$size_ok; $attempt++) {
	print "par.pl: Download attempt $attempt of $max_attempts\n";
	$mp3_length = download_and_convert($wav_filename, $mp3_filename, $stream,
		$artist, $album, $title, $year);

	$size_ok = ($mp3_length >= $min_length);
	if (!$size_ok) {
		print "par.pl: short output file - size($mp3_length), min_length($min_length)\n";
		if ($attempt != $max_attempts) {
			print "par.pl: waiting $retry_pause seconds before retrying\n";
			sleep $retry_pause;
		}
	}
}

# If still not big enough after a few goes, make the problem known.
if (!$size_ok) {
	my %mail = (To      => 'stuart@hickinbottom.demon.co.uk',
				From    => 'par@hickinbottom.demon.co.uk',
				Message => "Size was $mp3_length MB, minimum length is $min_length MB (tried $max_attempts times)",
				Subject => "WARNING: Recording of '$mp3_filename' appears short"
				);

	sendmail(%mail) or die $Mail::Sendmail::error;
}

exit 0;
	
sub download_and_convert($$$$$$$)
{
	my ($wav_filename, $mp3_filename, $stream,
		$artist, $album, $title, $year) = @_;

	# OK, now do the mplayer dump to the intermediate wav.
	system("/usr/bin/mplayer -vo null -ao pcm:file=\"$wav_filename\" \"$stream\"")  == 0
		or die "par.pl: mplayer failed to download WAV for programme: $?";

	# If that worked, we're going to LAME it to MP3.
	system("/usr/bin/sox -t wav \"$wav_filename\" -t wav - fade 2 | /usr/bin/pv | /usr/bin/lame --silent --preset 128 --tg \"Speech\" --ta \"$artist\" --tl \"$album\" --tt \"$title\" - \"$mp3_filename\"") == 0
		or die "par.pl: LAME failed to convert WAV to MP3: $?";

	unlink $wav_filename;

	# Set the year tag
	system("/usr/bin/id3v2 -y $year \"$mp3_filename\"") == 0 or die "par.pl: Failed to set year tag: $?";

	# Check the size and warn if it looks short
	my $mp3_length = (-s "$mp3_filename") / (1024 * 1024);
	return $mp3_length;
}
