#!/bin/sh

echo "===============================================================" >> /var/log/watch.log

echo `date +%F" "%T` "temp:" >> /var/log/watch.log
sensors | grep "temp1:" >> /var/log/watch.log

echo `date +%F" "%T` "cpu:" >> /var/log/watch.log
/bin/top -b | head -n 10 >> /var/log/watch.log

echo `date +%F" "%T` "mem:" >> /var/log/watch.log
/bin/free -m | grep "Mem:" >> /var/log/watch.log

echo `date +%F" "%T` "press:" >> /var/log/watch.log
ps -aux --sort=-rss | head -n 5 >> /var/log/watch.log


echo "===============================================================" >> /var/log/watch.log
