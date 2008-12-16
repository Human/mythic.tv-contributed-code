#!/usr/bin/perl

use strict;

# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# Email: bob@stormlogic.com
#
# See comments in DVB_fixer.sh for general comments about these scripts.

# If someone knows a way to do this in MySQL, PLEASE tell me - I'm a newbie
# when it comes to databases.

# LICENSE:
# --------------------------
# GPL, etc.  Full boilerplate to follow.

# USAGE:
# --------------------------
# This was built to be run by DVB_fixer.sh.  You can run it yourself if
# you know what you're doing.

# For each row of the channel table, do the following:
#
# If it's an NTSC row, pass it through unaltered
# If it's an HDTV row from zap2it, save it for later processing.
# If it's an HDTV row from a DVB channel scan, save it for later processing.
#
# Print out each zap2it-style row, merging with Scanned style if at all possible.
# Print out any Scanned rows that didn't match zap2it digital rows.

# Process the entire input, which is supposed to be passed in from
# DVB_fixer.sh or a user who knows what they're doing.

my %Zap2ItChannelTable=(); # stores ATSC zap2it channel listings
my %ScannedChannelTable=(); # stores ATSC scanned channel listings

# We'll do a single pass over the file to populate two hash tables,
# one for the zap2it-style rows and another for the DVB-style rows.
# Then we'll iterate over one table to look up the corresponding rows in
# the other table to make a merged row to send to stdout.

my @tmp;
my $channum;
my $freqid;
my $xmltvid;

# A scanned channel's channum will always be the zap2it-style's channum with the underscore removed.  This allows
# us to find out which zap2it-style row matches a scanned row.  So we'll index our hash tables based on the
# "standardized channum" which is the style with underscores removed.

while (<>) {
    chop();
    split(/\t/); # the text versions of SQL tables have columns separated by
    # tabs, so break this line up into an array, using tabs as the delimiter

    $channum = @_[1];
    $freqid = @_[2];
    $xmltvid = @_[9];
    if ($xmltvid eq "") { # no xmltvid: This is a scanned digital channel.
	# Put the scanned row into its own hash table indexed by the channum
	$ScannedChannelTable{$channum} = $_;
    } else { # it has an xmltvid; it could be zap2it NTSC, scanned, or zap2it HDTV
	# The _presence_ of an xmltvid does not guarantee that it _isn't_ a scanned channel.
	# Here are some ways of telling them apart when there is an xmltvid:

	@tmp = split(/_/,$channum);
	if ((@tmp[1] eq "") && ($channum eq $freqid)) { # If a listing has a channum with no underscore and a matching freqid, it's a
	    # zap2it-style NTSC channel listing.
	    # NTSC listing - send directly to stdout.
	    print $_,"\n";
	} else {
	    # zap2it-style digital channel listing.
	    @tmp = split(/-/,$freqid);
	   if (@tmp[1] != "") { # If a listing has a freqid with a hyphen...
	       @tmp = split(/_/,$channum);
	       if (@tmp[1] != "") { # ...and a channum with an undercore, it's a...
		   # zap2it digital listing
		   # Put the zap2it row into its own hash table indexed by the standardized channum.
		   $Zap2ItChannelTable{@tmp[0].@tmp[1]} = $_;
	       }
	   } else {
	       if ($freqid eq "\\N") {	# If a listing has a freqid of "\N", it's a scanned digital channel listing.
		   $ScannedChannelTable{$channum} = $_;
	       }
	   }
	}
    }
}

# Ok, now we've dumped the NTSC entries to stdout and have loaded up the entire digital portion
# of the channel table.  Now to make our merged version after we make sure it's even possible.

if ((keys %ScannedChannelTable) == 0) {
    print STDERR "ERROR: You have no scanned digital rows in your channel table.  Looks like you need to do a channel scan in mythtv-setup.\n";

    # print out the provided channel table unaltered
    foreach my $channum (keys %Zap2ItChannelTable) {
	print $Zap2ItChannelTable{$channum}, "\n";
    }
    exit (-2);
}

if ((keys %Zap2ItChannelTable) == 0) {
    print STDERR "ERROR: You have no zap2it-style digital channel rows in your channel table.  Either you're already converted or you need to run mythfilldatabase.\n";

    # print out the original channel table unaltered
    foreach my $channum (keys %ScannedChannelTable) {
	print $ScannedChannelTable{$channum}, "\n";
    }
    exit (-3);
}

# (The following column references to the channel table are 1-indexed.)
# Column 1 is the chanid.   DVB seems to have the wrong values here.  Happily, DVB doesn't
#          seem to care if we use the zap2it-style.
# Column 2 is the channum.  DVB seems to screw this up.  2_1 becomes 21, 11_1 becomes 111, etc.
#          Happily, DVB doesn't care if we un-screw it up.
# Column 3 is the freqid.  DVB seems to want it to be null.
# Column 5 is the callsign.  It's of the form CHANDT[2] from zap2it.  DVB likes it to look like CHAN-HD.
# Column 6 is the name.  It's of the form CHANDT[2] (CHAN-DT[2]) from zap2it.  DVB likes it to look like CHAN-HD.
# Column 10 is the xmltvid.  It's filled in by zap2it, but it's missing from the DVB channel scan.
# Column 21 is the mplexid.  The only criterion I can discern for it is that its number must match the first column in dtv_multiplex.
#          It has to be unique, but it otherwise doesn't se

# Here is a sample line in the default zap2it format:
# 1002	2_1	25-1	1	KDKADT	KDKADT (KDKA-DT)	none	\N		21248	0	32768	32768	32768	32768	Default	0	1		0	\N	\N	\N
# Here is what an entry for the same channel looks like from a DVB scan (note the absence of an xmltvid and the bad channum):
# 1055	21	\N	1	KDKA-HD	KDKA-HD	none	\N			0	32768	32768	32768	32768	Default	0	1		1	7	1	1

# And here is what the unified line looks like.  We mostly use the DVB version, but we take the chanid, channum, freqid, and xmltvidfrom the zap2it version.
# 1002	2_1	25-1	1	KDKA-HD	KDKA-HD	none	\N		21248	0	32768	32768	32768	32768	Default	0	1		1	7	1	1

# Print out each zap2it-style row, merging with Scanned style if at all possible
foreach my $channum (keys %Zap2ItChannelTable) {
    my @ScannedRow = split(/\t/,$ScannedChannelTable{$channum});
    my @Zap2ItRow = split(/\t/,$Zap2ItChannelTable{$channum});

    if (scalar @ScannedRow == 0) { # If there is no Scanned row for this Zap2It row, leave the Zap2It row alone
	print $Zap2ItChannelTable{$channum}, "\n";
    } else {
        # print out the merged row
	my $row = join "\t", @Zap2ItRow[(0..2)], @ScannedRow[(3..8)], @Zap2ItRow[9], @ScannedRow[(10..22)];
	print $row, "\n";

	# erase the entry from ScannedChannelTable
	delete $ScannedChannelTable{$channum};
    }
}

# Print out any Scanned rows that didn't match zap2it digital rows
foreach my $channum (keys %ScannedChannelTable) {
    print $ScannedChannelTable{$channum}, "\n";
}
