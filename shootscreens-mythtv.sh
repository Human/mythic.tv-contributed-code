#! /bin/bash 
# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# Email: bob@stormlogic.com
#
# If you run into problems with this script, please send me email

# This wrapper for shootscreens provides on-screen display feedback while screenshots
# are being generated.

# available sizes: 34, 25, 24, 20, 18, 17, 14, 12, 11, 10
export FONT="-adobe-helvetica-bold-*-*-*-34-*-*-*-*-*-*-*"
echo "This could take several minutes, depending on your" > /tmp/screens
echo "hardware and the number and type of videos you have." >> /tmp/screens
echo "It will only work on videos scanned with Video Manager." >> /tmp/screens 
cat /tmp/screens | osd_cat --font=$FONT --shadow=3 --pos=middle --align=centre --offset=200 --color=yellow --delay=0 &
shootscreens.sh 1
/bin/rm -f /tmp/screens