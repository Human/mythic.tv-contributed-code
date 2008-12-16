#!/bin/bash

# Written by Bob Igo from the MythTV Store at http://MythiC.TV
# with contributions from TJC and Sarah Hayes
# Email: bob@stormlogic.com
#
# If you run into problems with this script, please send me email

# This is alpha code to auto-generate thumbnails for previews in MythVideo.
# It won't currently work on some filenames that have spaces in them.
# It's surely just a matter of escaping or quoting, but I have yet to find
# the right incantation.

# example usage:
# find -L /myth/video -wholename '*.covers' -prune -o -name '*.resume' -o -type f -exec screenshooter.sh -v {} \;

# limitations:
# --
# In an MBE/SBE/FE setup this might get the settings for the wrong machine...
# The script has no AI to know if a grabbed frame is useful to identify the video, only that it was able to grab it.
# Doesn't clean up after itself if videos are deleted, though MythTV may do this on its own.
# Minimum theoretical compatible video length is 4 seconds.  Shorter videos will not work with this version.
# Surely more limitations I can't think of because it's my baby :)

Usage() {
    echo "USAGE:"
    echo `basename $0` "-v PATHNAME [-s SECONDS] [-c] [-b HOSTNAME] [-u USERNAME] [-p PASSWORD] [-o]"
    echo "-v: pathname to Video"
    echo "-s: number of Seconds to skip before capturing (270 by default)"
    echo "-c: Clobber any previous screenshot found for this video (off by default)"
    echo "-b: mysql server (Backend) hostname (localhost by default)"
    echo "-u: mysql Username (mythtv by default)"
    echo "-p: mysql Password (mythtv by default)"
    echo "-o: verbOse mode (off by default)"
    echo "-x: check for valid video eXtension (off by default)"
    echo
    echo "EXAMPLE: $0 -v /myth/video/HDTV/shuttle.mpg -c -s 30"
    exit 3
}

if [ -z $1 ]; then
    Usage
fi

V_MISSING=1

while getopts "v:sbupochx" FLAG ; do
    case "$FLAG" in
	v) VIDEO_PATHNAME="$OPTARG"
	    V_MISSING=0;;
	s) SKIPAHEAD="$OPTARG";;
	c) CLOBBER=1;;
	b) BACKEND_HOSTNAME="$OPTARG";;
	u) DBUSERNAME="$OPTARG";;
	p) DBPASSWORD="$OPTARG";;
	o) VERBOSE=1;;
	x) EXTENSION_CHECK=1;;
	*) Usage;;
    esac
done

if [ $V_MISSING == 1 ]; then
    Usage
fi

# Declaring Variables here and assigning sensible defaults.

# SKIPAHEAD is the number of seconds to skip ahead before starting the frame capture.
# Set it to an arbitrary value if none is specified.
SKIPAHEAD=${SKIPAHEAD:-"270"}
BACKEND_HOSTNAME=${BACKEND_HOSTNAME:-"localhost"}
DBUSERNAME=${DBUSERNAME:-"mythtv"}
DBPASSWORD=${DBPASSWORD:-"mythtv"}
# Defaults to quiet. 
VERBOSE=${VERBOSE:-0}  
# Unless otherwise told, do not clobber existing cover files.
CLOBBER=${CLOBBER:-0}
# Unless otherwise told, do not check the file extension against
# MythTV's list of registered video file types.
EXTENSION_CHECK=${EXTENSION_CHECK:-0}

VIDEO_CAPTURE_HOME=$(mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -sNBe "select data from settings where value='VideoArtworkDir' limit 1")
if [ ! -d "$VIDEO_CAPTURE_HOME" ] ; then
    echo "Directory $VIDEO_CAPTURE_HOME does not exist, nowhere to put the screen shot!"
    echo "Have you configured MythVideo yet?"
    exit 1
fi

VIDEO_HOME=$(mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -sNBe "select data from settings where value='VideoStartupDir' limit 1")
if [ ! -d "$VIDEO_HOME" ] ; then
    echo "Directory $VIDEO_HOME does not exist, nowhere to put the screen shot!"
    echo "Have you configured MythVideo yet?"
    exit 1
fi

VIDEO_FILENAME=$(basename "$VIDEO_PATHNAME")
VIDEO_EXTENSION=${VIDEO_FILENAME##*.}
# Since we cron'd lets first make sure the validity of the file
if [ "$EXTENSION_CHECK" == "1" ]; then
    EXCHECK=$(mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -sNBe "select f_ignore from videotypes where extension=\"$VIDEO_EXTENSION\";")
    #excheck returns blank, it found nothing.  
    if [ "$EXCHECK" == "" ]; then
	if [ "$VERBOSE" == "1" ]; then
	    echo "$VIDEO_EXTENSION does not appear to be a valid media file, skipping."
	fi
	exit 1
    else 
	# It is valid, but should we ignore it.  If so then excheck will equal 1.
	if [ "EXCHECK" == "1" ]; then 
	    if [ "$VERBOSE" == "1" ]; then
		echo "$VIDEO_EXTENSION is set to ignore."
	    fi
	    exit 1
	fi
	# It is valid, it's not set to ignore.  
	if [ "$VERBOSE" == "1" ]; then
	    echo "$VIDEO_EXTENSION appears in the Database, checking further."
	fi
	EXCHECK=$(mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -sNBe "select title from videometadata where filename=\"$VIDEO_PATHNAME\";")
	#Right, the file is supposed to be playable.  Has it been imported to the Db yet?
	if [ "$EXCHECK" == "" ] ; then
	    if [ "$VERBOSE" == "1" ]; then 
		echo "$VIDEO_FILENAME does not exist in the database."
	    fi  
	    exit 1
	# If you decide you want the system to 'auto import' the video then comment out 
	# the exit line and uncomment the rest of it.  Bewarned, this is sucky SQL at 
	# the best but will give sensible defaults.
	#
	#    if [ "$VERBOSE" == "1" ]; then
	#     echo "Importing $VIDEO_FILENAME in to database."
	#    fi
	#    mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -sNBe "insert into videometadata (intid, title, director, plot, rating, inetref, year, userrating, length, showlevel, filename, coverfile, childid, browse, playcommand, category) values (' ', '$VIDEO_FILENAME', 'Unknown', 'Unknown', 'NR', '00000000', 1895, 0.0, 0, 1, '$VIDEO_PATHNAME', 'No Cover', -1, 1, ' ', 0);"
	fi
    fi
fi

if [ "$CLOBBER" -eq 0 ]; then
      # Since we're not clobbering, first check to see if this video already has a coverfile entry in MySQL:
    SQL_CMD="select coverfile from videometadata where filename=\"$VIDEO_PATHNAME\";"
    CURRENT_COVERFILE=`mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -B -e "$SQL_CMD" | tail -1`
    
    if [[ "$CURRENT_COVERFILE" != "" ]] && [[ "$CURRENT_COVERFILE" != "No Cover" ]]; then
  	  # there's already a cover file for this video
  	if [ "$VERBOSE" == "1" ]; then 
	    echo "$VIDEO_FILENAME has cover file, skipping."
	fi
	exit 2
    fi
fi


# Swap the video file extension for png.  Should work assuming the extension only appears ONCE!
VIDEO_CAPTURE_PATHNAME="$VIDEO_CAPTURE_HOME/$VIDEO_FILENAME.png"

# How many frames of video to capture.  We'll grab the last frame as our screenshot.
if [ "$VIDEO_EXTENSION" == "m4v" ]; then
    FRAMES_TO_CAPTURE="90"
    SHOTFILE="000000"$FRAMES_TO_CAPTURE".png"
else
    FRAMES_TO_CAPTURE="05"
fi

SHOTFILE="000000"$FRAMES_TO_CAPTURE".png"
VIDEO_STATS="/tmp/screenshooter_video_stats.txt"

cd /tmp

# The video we're processing may be shorter than SKIPAHEAD seconds.
# Keep trying to capture until we find a SKIPAHEAD value within the length of the video.
# Give up if we reach 0 seconds.
while [ ! -f "$SHOTFILE" ]; do
    /usr/bin/mplayer -ss $SKIPAHEAD -vf scale=640:-2 -ao null -vo png -quiet -frames $FRAMES_TO_CAPTURE -identify "$VIDEO_PATHNAME" &> $VIDEO_STATS &
    TIMEOUT=9

    # Some video formats will play audio only. This loop gives the above command 20 seconds to
    # finish, otherwise it gets killed.
    while [ -n "`ps -p $! --no-heading`" ]; do
	TIMEOUT=$(expr $TIMEOUT - 1)
	if [ "$TIMEOUT" -le 0 ]; then
	    kill -9 $!
	    break
	fi
	sleep 1
    done
	    
    SKIPAHEAD=$(expr $SKIPAHEAD / 2)
    if [ "$SKIPAHEAD" -le 0 ]; then
	break
    fi
done

if [ -f "$SHOTFILE" ]; then
    # Now, the video_capture is taken, and the name of the shot is in $SHOTFILE
    # Rename it and move it to the place where video_captures live.
    /bin/mv -f "$SHOTFILE" "$VIDEO_CAPTURE_PATHNAME"
    /bin/rm -f 000000*png
    chown mythtv: "$VIDEO_CAPTURE_PATHNAME"

    # We've got the shotfile nailed, now calculate video run length.
    VIDEO_LENGTH_IN_SECONDS=`grep ID_LENGTH $VIDEO_STATS | awk -F'=' '{print $2}'`
    VIDEO_LENGTH_IN_INTEGER_SECONDS=${VIDEO_LENGTH_IN_SECONDS/%.*/}
    if [ $VIDEO_LENGTH_IN_INTEGER_SECONDS -lt 60 ]; then
	VIDEO_LENGTH_IN_MINUTES="1"
    else
	VIDEO_LENGTH_IN_MINUTES=$(expr $VIDEO_LENGTH_IN_INTEGER_SECONDS / 60)
    fi

    SQL_CMD="update videometadata set length=\"$MIN_LENGTH\" where filename=\"$VIDEO_PATHNAME\";"
    mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -e "$SQL_CMD"

    
    # put the screenshot pathname and any runlength info into videometadatatable

    # Pre-escape any single or double quotes for the SQL command.

    VIDEO_CAPTURE_PATHNAME=`echo $VIDEO_CAPTURE_PATHNAME | sed -e "s/'/\\\'/g" -e 's/"/\\\"/g' `
    VIDEO_PATHNAME=`echo $VIDEO_PATHNAME | sed -e "s/'/\\\'/g" -e 's/"/\\\"/g' `
    SQL_CMD="update videometadata set coverfile=\"$VIDEO_CAPTURE_PATHNAME\", length=\"$VIDEO_LENGTH_IN_MINUTES\" where filename=\"$VIDEO_PATHNAME\";"

    mysql -u $DBUSERNAME --password=$DBPASSWORD -h $BACKEND_HOSTNAME mythconverg -e "$SQL_CMD"
else
    echo "No image could be captured from $VIDEO_PATHNAME"
    exit 1
fi
