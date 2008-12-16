#!/bin/sh

# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# Email: bob@stormlogic.com
#
# If you run into problems with this script, please send me email and
# attach your $MyTempDir/unaltered_dtv_multiplex.txt file and $MyTempDir/unaltered_channel.txt files,
# and I'll see what I can do.  This script has had limited testing (see DISCLAIMER below).
#
# PURPOSE: 
# --------------------------
# At issue is the fact that digital channels scanned for use with DVB
# are missing xmltvids and generally have a few strangely-formatted columns.
# Merging the zap2it-style listings for a given channel with the scanned
# listings seems to be the best way to make sure you can use MythTV and
# avoid double entry of your channel data.
#
# There is a table called 'channel' in the MythTV MySQL database
# 'mythconverg'.  DVB expects entries in this table to look different
# than the way they are imported from zap2it.  This script
# reconciles this issue.

# DISCLAIMER:
# --------------------------
# This was tested on two setups: One with just an hd-3000 card and an OTA
# channel list; the second with an hd-3000 card, a PVR-350 card, and mix of
# NTSC, QAM, and ATSC channel listings.  This is more likely to work if
# you have a similar setup and less likely to work if you do not.
# Channels that have multiple subchannels may not work at all after the
# first subchannel, due to lack of test data.

# USAGE:
# --------------------------
# Fill in your broadcast listing information in mythtv-setup, then do a channel scan.
# Then run this script to convert your channel table into a format that both
# mythfilldatabase and DVB like.
#
# OR
#
# Fill in your broadcast listing information in mythtv-setup, run mythfilldatabase,
# then re-run mythtv-setup and do a channel scan.  Then run this script to convert
# your channel table into a format that both mythfilldatabase and DVB like.  (Not
# that you should go through all these steps, but this is to make it clear that if
# you have already installed and added zap2it channels, you can go back and do a channel
# scan to get the DVB-centric data.)
#
# See HELP, below, for command-line usage.

# LICENSE:
# --------------------------
# GPL, etc.  Full boilerplate to follow.

# THE SCRIPT
# --------------------------

# HELP
# --------------------------
# First, see if the user wants help.

if [[ $1 != "-undo" ]] && [[ $1 != "-nofill" ]] && [[ $1 != "" ]]; then
    echo "Run $0 after you've run mythtv-setup and have scanned for channels with its channel editor."
    echo "It won't hurt if you run mythfilldatabase first, but $0 will run it again anyway."
    echo ""
    echo "Use the \"-undo\" argument to undo what this script did to your channel and/or"
    echo "dtv_multiplex tables."
    echo "Use the \"-nofill\" argument if you don't want to run mythfilldatabase."
    exit 1;
fi

# Second, check to see if we're running on a system that even has DVB-capable
# tuner cards.
# If any of these modules are loaded, it means we have a DVB-capable card in
# the system:
# cx88_dvb, dvb-bt8xx, or51132

echo "$0: Testing to see if you have a DVB-capable card..."

# Quit if there's no DVB-capable card here.
if [[ `/sbin/lsmod | grep -c cx88s_dvb` == 0 ]]; then
    if [[ `/sbin/lsmod | grep -c dvb-bt8xx` == 0 ]]; then
	if [[ `/sbin/lsmod | grep -c or51132` == 0 ]]; then
	    echo "$0: ...and you do not, so this script won't run."
	    exit -1;
	fi
    fi    
fi

echo "$0: ...and you do, so we need to fix your channel database."

export MyTempDir="/root/tmp"

# Make sure our chosen tmp dir exists
if [[ ! -d $MyTempDir ]]; then
    if [[ -f $MyTempDir ]]; then # $MyTempDir is a file
	rm -f $MyTempDir
	echo "$0: Removing file $MyTempDir"
    fi
    echo "$0: Creating directory $MyTempDir"
    mkdir $MyTempDir
fi
chmod a+w $MyTempDir
echo "$0: (storing backups and temporary files in $MyTempDir)"
cd $MyTempDir

# What it means to fix the channel database depends on how we were invoked.
if [[ $1 == "-undo" ]]; then
    # We should do what we can to undo our previous actions.
    # First make sure we have some backup tables to revert to, then revert them.

    if [[ -f unaltered_channel.txt ]]; then
	# Delete the contents of the channel table, but not the table itself.
	mysql -e 'DELETE FROM channel;' mythconverg
	mv -f unaltered_channel.txt channel.txt
	# import the backup table into the mythconverg database
	mysqlimport -l -L -r mythconverg channel.txt
    else
	echo "$0: ERROR: the backup of the channel table does not exist."
	exit -2;
    fi

    if  [[ -f unaltered_dtv_multiplex.txt ]]; then
    	# Delete the contents of the dtv_multiplex table, but not the table itself.
	mysql -e 'DELETE FROM dtv_multiplex;' mythconverg
	mv -f unaltered_dtv_multiplex.txt dtv_multiplex.txt
	# import the backup table into the mythconverg database
	mysqlimport -l -L -r mythconverg dtv_multiplex.txt
    else
	echo "$0: ERROR: the backup of the dtv_multiplex table does not exist."
	exit -3;
    fi
else
    if [[ -f unaltered_channel.txt ]] || [[ -f unaltered_dtv_multiplex.txt ]]; then
	echo "$0: $0 has already been run at least once, and backup data exists."
	echo "$0: Please move $MyTempDir/unaltered_channel.txt and"
	echo "$0: $MyTempDir/unaltered_dtv_channel.txt"
	echo "$0: somewhere else so that it can be restored if necessary."
	exit -4;
    fi

    # Make sure to populate the channel table with zap2it-style entries.
    if [[ $1 != "-nofill" ]]; then
	su mythtv -c "mythfilldatabase --quiet"
    fi
    mysqldump --tab=$MyTempDir/ --opt mythconverg channel
    # Now $MyTempDir/channel.txt has what's in the channel table.

    # Do a sanity check to make sure the channel table isn't empty.  If it is,
    # then it means mythfilldatabase never successfully ran.
    if [[ `wc -c $MyTempDir/channel.txt | grep -ce "^0 "` == "1" ]]; then
	echo "$0: Your channel table is empty!  Make sure you have set up your channel source"
	echo "$0: and then run $0 without the '-nofill' flag."
	exit 2;
    fi

    # Save off a flat version of the channel table.
    /bin/cp -f channel.txt unaltered_channel.txt

    mysqldump --tab=$MyTempDir/ --opt mythconverg dtv_multiplex
    # Now $MyTempDir/dtv_multiplex.txt has what's in the dtv_multiplex table.
    # Save off a flat version of the dtv_multiplex table.
    /bin/cp -f dtv_multiplex.txt unaltered_dtv_multiplex.txt
 
    # Just replace the manual edits that the user would otherwise
    # have to do as part of the usual DVB workaround.  
    cat unaltered_channel.txt | DVB_channel_converter.pl | sort > channel.txt

    # We now have an altered channel table we need to put back into mysql.
    # Put our new entries in place
    mysql -e 'DELETE FROM channel;' mythconverg
    mysqlimport -l -L -r mythconverg channel.txt
    
    # If something goes horribly wrong, run this as root to examine your channel table:
    # mysql -e 'SELECT * FROM channel' mythconverg
    
    echo "$0: If you want to undo the effects of this script, run '$0 -undo'"
    echo "$0: with your desired backup tables (unaltered_channel.txt and"
    echo "$0: unaltered_dtv_multiplex.txt) in $MyTempDir."
fi