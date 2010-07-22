#!/usr/bin/perl

use Shell;
use strict;
use POSIX qw(floor);

# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# including some original code and contributions from Nick C.
# and graysky.
# Email: bob@stormlogic.com
#
# If you run into problems with this script, please send me email

# PURPOSE:
# --------------------------
# This is a wrapper script that tries to find the best parameters
# for calling an underlying video player.  The outer layer determines
# the best playback parameters, while the inner layer picks the best
# player to call.

# RATIONALE:
# --------------------------
# Default video playback options are not optimal on all hardware or
# for all video types.  In addition, common video players do not
# offer to bookmark video so that you can resume where you left off.
# Both of these problems can be addressed by this wrapper.

# PARAMETERS:
# --------------------------
# The same parameters you'd use for mplayer, some of which may be
# translated automatically for use with smplayer.

# FILES:
# --------------------------
# $mediafile, the file to play

sub run () {
    my $mediafile = @ARGV[$#ARGV];
    my $player = &pick_player();

    # mplayer evaluates configuration options in the following order, with
    # later-evaluated options overriding earlier-evaluated ones, both within
    # a given configuration location and between them:
    # 1) system-wide configuration/profiles, /etc/mplayer/mplayer.conf
    # 2) user-specific configuration/profiles, ~/.mplayer/config
    # 3) commandline configuration parameters
    # 4) file-specific configuration, ~/.mplayer/[filename].conf
    # 5) any nonstandard configuration file, included via "-include" parameter
    #
    # This script's dynamic configuration options fall in at 2.5 above,
    # so commandline options, file-specific configuration options,
    # or a nonstandard configuration file will override the options that
    # the script creates, but system-wide and user-specific configuration
    # will be overridden by the dynamic configuration options.
    #
    # This is sub-optimal, as the easiest way for a user to compensate for
    # a misfiring configuration rule would be to override it in a configuration
    # file.  Instead, they will have to change the way they run this script.

    my $player_parameters = join(' ',
				 &dynamic_parameters($mediafile),
				 &translate_parameters($player,@ARGV[0..$#ARGV-1]));
    &player($player,$player_parameters,$mediafile);
}

&run();

# Translates any parameters into ones that will be compatible with the given player.
sub translate_parameters() {
    my($player,@parameters)=@_;

    if ($player eq "smplayer") {
	# Stupidly, smplayer uses a different set of command-line parameters than generic
	# mplayer, so we need to translate mplayer-centric ones into the few that are
	# available in smplayer-ese.
	my %smplayer_parameter_translation_array = (
	    "-fs" => "-fullscreen",
	    "-zoom" => " "
	    );
	
	sub translate() {
	    my($flag)=@_;
	    return $smplayer_parameter_translation_array{$flag};
	}
	
	return map(&translate($_), @parameters);
    } else {
	# currently, all other players used by this wrapper work with mplayer parameters
	return @parameters;
    }
}

# Returns an array of dynamic parameters based on the media type,
# the presence of special playback decoding hardware, and the
# general capability of the CPU.
sub dynamic_parameters () {
    my($mediafile)=@_;
    my @parameters = ();
    my $codec="";
    my $xresolution=0;
    my $yresolution=0;
    my $aspect_ratio=0.0;
    my %vdpau_supported_modes=();
    my $vf_parameters="";

    # See if the GPU and driver support vdpau for GPU-based accelerated decoding
    my $command="vdpauinfo |";
    # On supported hardware, vdpinfo produces relevant results that look something like this (see
    # http://www.phoronix.com/forums/showthread.php?t=14493 for additional details, or run
    # vdpinfo on vdpau-capable hardware yourself):
    #
    #MPEG1             0  2  4096  4096
    #MPEG2_SIMPLE      3  2  4096  4096
    #MPEG2_MAIN        3  2  4096  4096
    #H264_MAIN        41  4  4096  4096
    #H264_HIGH        41  4  4096  4096
    
    my $grabbing_modes=0;
    open(SHELL, $command);
    while (<SHELL>) {
	chop;
	if (m/Decoder Capabilities/gi) {
	    $grabbing_modes=1;
	    #print "*** MODES START NOW"
	} elsif (m/Output Surface/gi) {
	    $grabbing_modes=0;
	} elsif ($grabbing_modes) {
	    if (m/[A-Z]+[0-9]+/g) {
		s/(_.*)//g;
		#print "*** GRABBED MODE $_\n";
		$vdpau_supported_modes{$_} = 1;
	    }
	}
    }
    close(SHELL);
    
    # Learn some things about the video: codec, aspect ratio, and resolution
    my $command="mplayer -identify -frames 1 -vo null -ao null \"$mediafile\" |";
    open(SHELL, $command);
    while (<SHELL>) {
	chop;
	if (m/ID_VIDEO_CODEC=(.*)/g) {
	    $codec = $1;
	    #print "DEBUG: codec is $codec\n";
	} elsif (m/ID_VIDEO_WIDTH=(.*)/g) {
	    $xresolution = $1;
	    #print "DEBUG: x resolution is $xresolution\n";
	} elsif (m/ID_VIDEO_HEIGHT=(.*)/g) {
	    $yresolution = $1;
	    #print "DEBUG: y resolution is $yresolution\n";
	} elsif (m/ID_VIDEO_ASPECT=(.*)/g) {
	    $aspect_ratio = $1;
	}
    }
    close(SHELL);

    # see if it's a 4:3 video
    if ($aspect_ratio =~ m/1\.3\d*/) {
	# see if it's a malformed 4:3 video with top and side bars, in need of cropping
	my $crop_candidate="";
	my $biggestX=0;
	my $biggestY=0;
	# The algorithm here is trial and error.  Skip 6 minutes into a video, and look at 40 frames of
	# video.  Videos shorter than 6 minutes will not end up being examined for letterboxing badness.
	# In a longer video, use the least-recommended pruning that mplayer suggests, among the frames polled.
	my $command="mplayer -ss 360 -ao null -vo null -vf cropdetect -frames 40 \"$mediafile\" | grep CROP | tail -1 |";
	open(SHELL, $command);
	while (<SHELL>) {
	    if (m/-vf (crop=.*)\)/g) {
		$crop_candidate = $1;
		#print "DEBUG: $crop_candidate\n";
		if ($crop_candidate =~ m/(\d+):(\d+)/) {
		    if (($1 > $biggestX) && ($2 > $biggestY)) {
			$biggestX = $1;
			$biggestY = $2;
			#print "DEBUG newX: $biggestX\n";
			#print "DEBUG newY: $biggestY\n";
		    }
		}
	    }
	    if (($biggestX != $xresolution) || ($biggestY != $yresolution)) {
		$vf_parameters = $crop_candidate;
	    }
	    #print "DEBUG: crop parameter is $vf_parameters\n";
	}
	close(SHELL);
    }

    # If there are no crop parameters, use vdpau if it's supported.  Don't use vdpau if there's cropping
    # because vdpau doesn't work with mplayer's cropping video filter.

    # We should use vdpau if it's available and helps with the codec we need to decode.
    if ($vf_parameters eq "") {
	if ($codec eq "ffh264") { # h.264
	    if ($vdpau_supported_modes{"H264"}) {
		push(@parameters, "-vo vdpau");
		push(@parameters, "-vc ffh264vdpau");
	    }
	} elsif ($codec eq "ffmpeg2") { # MPEG2
	    if ($vdpau_supported_modes{"MPEG2"}) {
		push(@parameters, "-vo vdpau");
		push(@parameters, "-vc ffmpeg12vdpau");
	    }
	    
	    # ??? although MPEG1 is rare, it seems as if it should work with -vc ffmpeg12vdpau as well
	    
	    # problems have been reported with WMV3 support
	    
#    } elsif ($codec eq "ffwmv3") { # WMV3
#	if ($vdpau_supported) {
#	push(@parameters, "-vo vdpau");
#	push(@parameters, "-vc ffwmv3vdpau");
#    }
	    # problems have been reported with WVC1 support
	    
#    } elsif ($codec eq "ffvc1") { # WVC1
#	if ($vdpau_supported) {
#	push(@parameters, "-vo vdpau");
#	push(@parameters, "-vc ffvc1vdpau");
#    }
	    
	} else { # any codec that doesn't work with vdpau
	    push(@parameters, "-vo xv,x11,");
	    push(@parameters, "-vc ,");
	    push(@parameters, "-vf pp=lb,$vf_parameters");
	}
    } else { # there is a crop parameter
	push(@parameters, "-vo xv,x11,");
	push(@parameters, "-vc ,");
	push(@parameters, "-vf pp=lb,$vf_parameters");
    }
    return(@parameters);
}

# Find the best player for use on this system.  The script prefers smplayer,
# which has built-in bookmarking, falling back to mplayer-resumer.pl, which
# implements bookmarking as an mplayer wrapper, if smplayer cannot be found.
# Finally, if no bookmarking players can be found, a barebones mplayer is used.
sub pick_player () {
    #my @possible_players = ("smplayer", "mplayer-resumer.pl", "mplayer");
    my @possible_players = ("mplayer-resumer.pl", "mplayer");
    my $command;
    my $candidate_player;
    foreach (@possible_players) {
	$candidate_player = $_;
	$command = "which $candidate_player |";
	open(SHELL, $command);
	if (<SHELL>) {
	    #print "player $candidate_player : $_\n";
	    return $candidate_player;
	}
	close(SHELL);
    }
}

# Calls player
sub player () {
    my($player,$parameters,$mediafile)=@_;
    my $command = "$player $parameters \"$mediafile\" 2>&1 |";

    print "DEBUG: $0's player command is: *** $command ***\n";
    open(SHELL, $command);
    while (<SHELL>) {
	print $_;
    }
    close(SHELL);
}
