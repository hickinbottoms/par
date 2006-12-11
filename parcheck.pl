#!/usr/bin/perl

# Script to check downloads made from the par.pl script. If this checking
# script is periodically run it will detect if a programme has been skipped.
#
# Note that this script currently assumes that programmes are downloaded
# weekly (ie every seven days). With more advanced crontab parsing that
# restriction could be removed.
#
# Copyright (c) Stuart Hickinbottom 2006

use warnings;
use strict;
use Config::Crontab;
use Getopt::Long;
use Mail::Sendmail;

use constant MAXAGE => 7.0;
use constant NOAGE => 10000;
use constant MARKER => '.checkpar';
use constant FROM => 'checkpar@hickinbottom.demon.co.uk';
use constant SMTP => 'post.demon.co.uk';

my $verbose;
my $mailto;
GetOptions('verbose' => \$verbose,
	'mailto=s' => \$mailto);

my $ct = new Config::Crontab;
$ct->read;

# Find all the par.pl lines that are active.
for my $line ($ct->select(-command_re => 'par.pl', -active => 1)) {
	# Identify the directory that was being recorded to.
	my $command = $line->command;
	if ($command =~ /--outputdir ?"(.*?)"/) {
		my $dir = $1;
		print "Processing directory $dir\n" if $verbose;

		# Now find all the files (not directories) in those directories and
		# process them.
		opendir(DIR, $dir);
		my @names = readdir(DIR);
		my $newest = NOAGE;
		my $newest_file;
		foreach my $name (@names) {
			if (-f "$dir/$name") {
				my $age = -M "$dir/$name";
				if ($age < $newest) {
					$newest = $age;
					$newest_file = "$dir/$name";
				}
			}
		}

		print "Newest file in $dir is $newest days old\n" if $verbose;

		# If the newest is older than the threshold, then a recording might
		# be missing.
		if (($newest > MAXAGE) and ($newest != NOAGE)) {
			print "$dir may be missing a recording\n" if $verbose;

			if ((! -f "$dir/" . MARKER) || (-M ("$dir/" . MARKER) > -M $newest_file)) {

				# Create/update the marker file. We do this so we don't
				# keep reminding the user.
				open(FILEHANDLE, ">$dir/" . MARKER) || die('Cannot create file: ' . $!);
				close(FILEHANDLE);

				# Alert the user.
				if ($mailto) {
					print "Sending notification to $mailto\n" if $verbose;
					my %mail = (
						To => $mailto,
						From => FROM,
						smtp => SMTP,
						Subject => "Possible recording missing from $dir",
						Message => "There might be a recording missing from '$dir' - the newest recording in that directory is " . int($newest) . " days old"
					);
					sendmail(%mail) or die $Mail::Sendmail::error;
				}
			}
		} else {
			print "But user user has already been warned so not doing so again\n" if $verbose;
		}
	}
}
