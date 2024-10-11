#!/bin/bash

LANAC_NAME=lanac
UPDATE_NAME=update

# 关闭lanac主进程
echo "Close '$LANAC_NAME', CMD: \"pkill -15 $LANAC_NAME\""
pkill -15 $LANAC_NAME

processcount=`ps -ef|grep $LANAC_NAME |grep -v grep | grep -v .sh|wc -l`
if [ $processcount -gt 0 ];
then
    kill -s 9 `ps -ef | grep "$LANAC_NAME" |grep -v grep | grep -v .sh | awk '{print $2}'`
fi


echo "Close '$UPDATE_NAME', CMD: \"pkill -15 $UPDATE_NAME\""
pkill -15 $UPDATE_NAME

processcount=`ps -ef|grep $UPDATE_NAME |grep -v grep | grep -v .sh|wc -l`
if [ $processcount -gt 0 ];
then
    kill -s 9 `ps -ef | grep "$UPDATE_NAME" |grep -v grep | grep -v .sh | awk '{print $2}'`
fi