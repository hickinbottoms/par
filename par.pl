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

print 'par: $Id$' . "\n";

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
		"dirbase=s" => \$basedir,
		"artist=s" => \$artist,
		"title=s" => \$basename,
		"minlength=i" => \$min_length,
		"maxtries=i" => \$max_attempts,
		"retrypause=i" => \$retry_pause,
		"bitrate=i" => \$bitrate,
		"format=s" => \$format,
		"help|?" => sub { pod2usage(-verbose => 3) })
	or die "Failed to understand command options";

# Some options are mandatory.
pod2usage(2) if not ($stream || $basedir || $artist || $basename || $min_length);

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
my $wav_filename = tmpnam();
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
#	system("/usr/bin/mplayer -vo null -ao pcm:file=\"$wav_filename\" \"$stream\"");

#	my $length = length_minutes($wav_filename);
#	if ($length < $min_length) {
#		print "par: short output file - $length minutes, min length $min_length minutes\n";
#		$converted_ok = 0;
#	}
$wav_filename = "/home/stuarth/code/audiothings/par/test2.wav";

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

#	unlink $wav_filename;

	return ( $converted_ok, $length );
}

sub length_minutes($) {
	my $file = shift;

	my $wav = new Audio::Wav;
	my $read = $wav->read($file);
	return int($read->length_seconds() / 60);
}


# The help text
__END__

=head1 NAME

FLACulance.pl [options]

=head1 SYNOPSIS

Script to find all FLAC files, then compute and store album and track
"Replay Gain" (http://en.wikipedia.org/wiki/Replay_Gain) tags for each album.

=head1 OPTIONS

=over 15

=item --help

Show this help description

=item --verbose

Output far more progress messages during processing - useful when trying to
track down problems

=item --directory

Override default location of input directory. If no directory is specified then
a default music directory will be used instead

=back

=head1 EXAMPLE

FLACulance.pl --verbose --directory="c:\my music"

=cut

