#!/usr/bin/bash

################################################################################
# mystartup.sh
#
# This shell program is for testing a startup like rc.local using systemd.
# By David Both
# Licensed under GPL V2
#
################################################################################

# This program should be placed in /usr/local/bin

################################################################################
# This is a test entry

/usr/local/bin/fbi_display.sh &

echo `date +%F" "%T` "Startup worked" >> /var/log/mystartup.log
