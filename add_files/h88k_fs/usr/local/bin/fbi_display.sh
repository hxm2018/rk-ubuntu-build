#!/bin/bash

export LC_ALL=en_US.UTF8
modprobe fb_st7789v
fbdev=/dev/fb1
if [ ! -c $fbdev ];then
	echo "$fbdev is not exists!"
	exit 1
fi

if ! dpkg -l imagemagick >/dev/null 2>&1;then
	echo "imagemagick not installed!"
	exit 1
fi

if ! dpkg -l fbi >/dev/null 2>&1;then
	echo "fbi not installed!"
	exit 1
fi

SIZE=240x135
tty=6
delay=3

function display_img() {
	local fbdev=$1
	local tty=$2
	local img=$3
	local delay=$4
	local rm_img=$5
	local pid=""
	local size=$(identify -format "%wx%h" $img 2>/dev/null)
	if [ "$size" != "" ];then
		case $size in 
			$SIZE) zoom=""
				;;
			    *) zoom="-autozoom"
				;;
		esac
		fbi -d $fbdev -T $tty $zoom $img >/dev/null 2>&1 &
		sleep $delay
		pid=$(ps -ef | grep "fbi \-d" | grep -v grep | awk '{print $2}')
		[ "$pid" != "" ] && kill $pid 2>/dev/null
		if [ "$rm_img" == "1" ];then
			rm $img
		fi
	fi
}

# Blank screen
img=$(mktemp --suffix='.png')
convert -size $SIZE \
       	xc:black \
       	-fill white \
       	-pointsize 36 \
       	-gravity NorthWest \
	-draw 'text 20,24 ""' \
       	$img
display_img $fbdev $tty $img 1 1

# Hello world
img=$(mktemp --suffix='.png')
convert -size $SIZE \
       	xc:red \
       	-fill white \
       	-pointsize 36 \
       	-gravity NorthWest \
	-draw 'text 20,24 "Hlink H88K"' \
       	-draw 'text 20,64 "Hello world!"' \
       	$img
display_img $fbdev $tty $img $delay 1

# Date & time
img=$(mktemp --suffix='.png')
day=$(date +%Y-%m-%d)
time=$(date +"  %H:%M:%S  ")
convert -size $SIZE \
       	xc:blue \
       	-fill white \
       	-pointsize 36 \
       	-gravity NorthWest \
	-draw "text 20,24 \"$day\"" \
       	-draw "text 20,64 \"$time\"" \
       	$img
display_img $fbdev $tty $img $delay 1

# Images
for img in /usr/local/share/h88k/imgs/*;do
	display_img $fbdev $tty $img $delay 0
done
