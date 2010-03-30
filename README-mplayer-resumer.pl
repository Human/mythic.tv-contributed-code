Copy mplayer-resumer.pl to /usr/local/bin/ on your media box.

Run "chmod a+x" on it to make it executable.

If using MythTV, go into your MythTV settings and replace all instances of the mplayer command with mplayer-resumer.pl, making sure to remove the '--quiet' parameter, if used. All other parameters seem to be compatible with the resumer.

Watch a video on your HDD, and exit. When you re-play it, it should start playing almost exactly where you stopped.

RECOMMENDED: Try using mplayer-wrapper.pl instead, which attempts to pick the best parameters for playing your video, and then calls mplayer-resumer.pl.

Send us dark chocolate (60-80% cocoa) if you like this program.

For questions, contact Bob Igo : Bob.Igo@DigitalArcSystems.com
