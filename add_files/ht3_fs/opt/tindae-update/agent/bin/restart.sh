#!/bin/bash
work_path=$(dirname $(readlink -f $0))
sh ${work_path}/stop.sh
nohup sh ${work_path}/start.sh > /dev/null 2>&1 &
echo '重启成功!'