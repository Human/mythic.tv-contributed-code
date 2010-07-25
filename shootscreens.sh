#!/bin/bash

# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# Email: bob@stormlogic.com
#
# If you run into problems with this script, please send me email

# This code generates screenshots (cover files) for all videos in
# MythTV's videometadata table that do not have covers associated with them.

if [ "$1" == "1" ]; then
    OSD=1
else
    OSD=0
fi

> /tmp/shooter.log
{
    percentage=0
    # Change IFS to be a newline so that filenames with spaces will be handled properly.
    IFS=$'\n'
    vidcount=`mysql -u root mythconverg -B -e "select filename from videometadata where coverfile=\"No Cover\" OR coverfile=\"\";" | wc -l`
    increment=$(expr 100 / $vidcount)
    for vid in `mysql -u root mythconverg -B -e "select filename from videometadata where coverfile=\"No Cover\" OR coverfile=\"\";" | grep -v -e "^filename$"`
    do
      if [ $OSD == 1 ]; then
	osd_cat --barmode=percentage --percentage=$percentage --pos=middle --align=center --color=white --text="Generating Video Thumbnails..." --font=$FONT --shadow=3 --color=yellow --delay=0 &
	percentage=$(expr $percentage + $increment)
      fi

      screenshooter.sh -v $vid
    done
    if [ $OSD == 1 ]; then
	killall -9 osd_cat
	osd_cat --barmode=percentage --percentage=100 --pos=middle --align=center --color=white --text="Video Thumbnails Generated!" --font=$FONT --shadow=3 --color=yellow --delay=3 &
    fi
}