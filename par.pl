#!/usr/bin/perl

# Script to download and store BBC 'listen again' radio content, transcoding
# that recording into any format you care to mention (well, any format
# supported by the Perl Audio Converter at any rate!).
#
# Combine this script with cron for your very own Personal Audio Recorder
# (hence the name of this script).

use warnings;
use strict;
use POSIX qw(strftime tmpnam);
use File::Path;
use Pod::Usage;

# Check and show an error if required modules can't be found.
eval 'use File::Which'; die 'Missing required component \'dev-perl/File-Which\'' if $@;
eval 'use Getopt::Long'; die 'Missing required component \'perl-core/Getopt-Long\'' if $@;
eval 'use Mail::Sendmail'; die 'Missing required component \'dev-perl/Mail-Sendmail\'' if $@;
eval 'use LWP'; die 'Missing required component \'dev-perl/libwww-perl\'' if $@;
eval 'use LWP::UserAgent'; die 'Missing required component \'dev-perl/libwww-perl\'' if $@;
eval 'use Audio::Wav'; die 'Missing required component \'dev-perl/Audio-Wav\'' if $@;

use constant DEFAULT_ATTEMPTS => 5;
use constant DEFAULT_RETRY => 300;
use constant DEFAULT_FORMAT => 'mp3';
use constant DEFAULT_BITRATE => 128;
use constant PACPL => 'pacpl';

sub download_and_convert($$$$$$$$$$);

# We rely on the Perl Audio Converter for the heavy lifting, so ensure it's
# present on the path.
my $pacpl = which(PACPL);
if (not defined($pacpl)) {
	printf STDERR "par: The Perl Audio Converter is required to support this script\n";
	printf STDERR "par: Download it from http://sourceforge.net/projects/pacpl/\n";
	printf STDERR "par: It doesn't require compilation, but use the following command to install\n";
	printf STDERR "par:     sudo ./pacpl-install --install base\n";
	exit 1;
}

# Process command-line arguments
my $stream;
my $basedir;
my $artist;
my $basename;
my $min_length;
my $max_attempts;
my $retry_pause;
my $bitrate;
my $format;
GetOptions("stream=s" => \$stream,
		"outputdir=s" => \$basedir,
		"artist=s" => \$artist,
		"title=s" => \$basename,
		"minlength=i" => \$min_length,
		"maxtries=i" => \$max_attempts,
		"retrypause=i" => \$retry_pause,
		"bitrate=i" => \$bitrate,
		"format=s" => \$format,
		"help|?" => sub { pod2usage(-verbose => 1) })
	or die "Failed to understand command options";

# Some options are mandatory.
die "par.pl: Mandatory options missing - try 'perldoc par.pl'" unless ($stream || $basedir || $artist || $basename || $min_length);

print 'par: $Id$' . "\n";

# Some options default.
$max_attempts = $max_attempts || DEFAULT_ATTEMPTS;
$retry_pause = $retry_pause || DEFAULT_RETRY;
$format = $format || DEFAULT_FORMAT;
$bitrate = $bitrate || DEFAULT_BITRATE;

# Display what we're using:
print "par: stream: $stream\n";
print "par: format: $format\n";
print "par: bitrate: $bitrate\n";
print "par: base directory: $basedir\n";
print "par: artist: $artist\n";
print "par: title: $basename\n";
print "par: minlength: $min_length\n";
print "par: maxtries: $max_attempts\n";
print "par: retrypause: $retry_pause\n";
print "par: pacpl: $pacpl\n";

# If this is a RAM file, need to download that to discover the embedded stream.
if ($stream =~ /^http:\/\//) {
	print "Downloading '$stream'\n";
	my $ua = LWP::UserAgent->new;
	$ua->agent("par/0.1 ");

	# Create a request
	my $req = HTTP::Request->new(GET => $stream);
	my $res = $ua->request($req);
	 
	if ($res->is_success) {
		$stream= $res->content;
	} 
	else {
		die "Could not download '$stream'";
	}
}

# Crack the current time.
my @time_now = gmtime;
my $date = strftime "%G-%m-%d", @time_now;
my $week = strftime "%U", @time_now;
my $year = strftime "%G", @time_now;

# Make the output directory (if necessary)
( -d "$basedir" ) or mkpath($basedir)
	or die "par: can't make output directory $basedir";

# Filenames
my $wav_filename = tmpnam() . '.wav';
my $output_filename = "$basedir/$date $basename.$format";

# File tags
my $album = "$basename";
my $title = "$date $basename";

print "par: recording to $output_filename\n";

# Try a few times to download and convert - sometimes the download is
# truncated early.
my $converted_ok = 0;
my $length = 0;
for (my $attempt = 1; ($attempt <= $max_attempts) && !$converted_ok; $attempt++) {
	print "par: download attempt $attempt of $max_attempts\n";
	($converted_ok, $length) = download_and_convert($pacpl, $wav_filename, $output_filename, $stream, $bitrate,
		$artist, $album, $title, $year, $min_length);

	if (!$converted_ok && ($attempt != $max_attempts)) {
		print "par: waiting $retry_pause seconds before retrying\n";
		sleep $retry_pause;
	}
}

# If still not big enough after a few goes, make the problem known.
if (!$converted_ok) {
	my %mail = (To      => 'stuart@hickinbottom.demon.co.uk',
				From    => 'par@hickinbottom.demon.co.uk',
				Message => "Size was $length mins, minimum length is $min_length mins (tried $max_attempts times)",
				Subject => "ERROR: Recording of '$output_filename' cancelled because download was too short"
				);

	if (!sendmail(%mail)) {
		# This is purposefully done twice to avoid the warning from perl
		# that the symbol is only used once (an artifact, I suspect, of the
		# eval trick used at the head of this script).
		my $error = $Mail::Sendmail::error;
		$error = $Mail::Sendmail::error;
		die $error;
	}
}

print "par: all done\n";

exit 0;
	
sub download_and_convert($$$$$$$$$$)
{
	my ($pacpl, $wav_filename, $output_filename, $stream, $bitrate,
		$artist, $album, $title, $year, $min_length) = @_;

	my $converted_ok = 1;

	# OK, now do the mplayer dump to the intermediate wav.
	system("/usr/bin/mplayer -vo null -ao pcm:file=\"$wav_filename\" \"$stream\"");

	my $length = length_minutes($wav_filename);
	if ($length < $min_length) {
		print "par: short output file - $length minutes, min length $min_length minutes\n";
		$converted_ok = 0;
	}

	# If that worked, we're going to use pacpl to get to our destination
	# format and apply the required tags.
	if ($converted_ok) {
		my $cmd = "pacpl --convertto $format --overwrite --outfile \"$output_filename\" --file \"$wav_filename\"";
		print "par: $cmd\n";
		system($cmd);
		if (! -f "$output_filename") {
			die "par: Perl Audio Converter failed to convert WAV file";
		}
		$cmd = "pacpl --tag genre=Speech --tag artist=\"$artist\" --tag title=\"$title\" --tag album=\"$album\" --tag year=\"$year\" \"$output_filename\"";
		print "par: $cmd\n";
		system($cmd);
	}

	unlink $wav_filename;

	return ( $converted_ok, $length );
}

sub length_minutes($) {
	my $file = shift;

	my $wav = new Audio::Wav;
	my $read = $wav->read($file);
	return int($read->length_seconds() / 60);
}

__END__

# The help text

=head1 NAME

par.pl [options]

=head1 SYNOPSIS

Script to download streams in Real Audio format and transcode them to
a format of the users' choice. The output audio file is also appropriately
tagged.

The main use of this script (and its original purpose) was to implement a
"poor man's personal audio recorded" by coupling this script to cron. In
particular, this is very useful for the BBC's "listen again" content since
that allows you to record each programme as they come out (if you schedule
your cron job correctly).

Each recorded programme is given a filename that includes the date of the
recorded programme, hence if you use this correctly you'll end up with 
folder that contains all the recorded episodes of the programme you were
interested in.

=head1 OPTIONS

=over 15

=item --stream

The URL of the Real Audio stream to record. This can end in either F<.ra>
or F<.ram> - both will be correctly handled.

=item --outputdir

The directory used for the output files - this script will place each
recorded programme into this folder with a filename that includes the
date that the recording was made.

=item --format

The required output format. This can be any format that is recognised as
a 'convertto' type by the Perl Audio Converter script (pacpl), but the most
common types to use here would be "ogg" or "mp3".

This parameter is optional; if it is not present then MP3 format is the
default.

=item --artist

The artist name to tag the output file with. For radio stations, this is
often going to be the station name the programme has been recorded from
(eg "BBC Radio 4").

=item --title

The title that will be written into the track tag of the recording (with
the date of the recording as a prefix). For radio stations, this is often
going to be the name of the programme itself (eg "The Archers Omnibus").

=item --minlength

Specifies the minimum length, in minutes, that the programme is expected to
be. This is useful since a remote steam can be prematurely closed and would
otherwise result in a part-recorded programme. If the recording is less
than this number of minutes then the script will try to download the
programme again, up until the number of tries in the next option.

=item --maxtries

This specifies the maximum number of tries that will be used to download the
programme. This value is optional; if not specified then the maximum
number of tries will be 5.

=item --retrypause

If the download has to be retried, this value specifies the amount of time,
in seconds, that the script will pause before retrying the download. This
value is optional; if not specified then the pause will be 300s (five
minutes).

=item --bitrate

Specifies the required bitrate (in kbps) of the resulting file. This value
is optional and if not supplied the default of 128kbps will be used instead.

=item --help

Displays usage information for the script.

=back

=head1 EXAMPLE

A simple example is probably all you'll need to actually use this script
effectively. The following command will download a programme that is published
weekly and transcode it to Ogg format:

 par.pl \
  --stream "rtsp://rmv8.bbc.net.uk/radio4/archers/archers_omnibus.ra" \
  --outputdir "/mnt/media/Radio/archers" \
  --artist "BBC Radio 4" \
  --title "The Archers Omnibus" \
  --minlength 73 \
  --format ogg

Over time (eg if this command were scheduled weekly with cron), this will
populate the folder F</mnt/media/Radio/archers> as follows:

 2006-08-27 The Archers Omnibus.ogg
 2006-09-03 The Archers Omnibus.ogg
 2006-09-10 The Archers Omnibus.ogg

=head1 DEPENDENCIES

As well as the main dependencies of this script (which should be detected and
a meaningful error produced if they are not present), there are a number of
other dependencies that must be installed for this script to work:

=over 5

=item Perl Audio Converter

This can be obtained from L<http://sourceforge.net/projects/pacpl> - there is
no Gentoo ebuild available. Follow the installation instructions with the
package (note, though, that only a "base" installation is necessary for
this script's purposes).

=item Ogg::Vorbis::Header

Only necessary if you intend to produce Ogg files with "--format ogg".
Gentoo ebuild dev-perl/ogg-vorbis-header can be used to install this.

=item MP3::Tag

Only necessary if you intend to produce MP3 files with "--format mp3" (or
leave the default format, which is MP3). Gentoo ebuild dev-perl/MP3-Tag can
be used to install this.

=back

Plus, any other dependencies of the Perl Audio Converter for your chosen
output format - determine those by running "pacpl-install -c" in the
installation package (the required Perl modules are listed at the end).

=head1 AUTHOR

Stuart Hickinbottom

=cut

