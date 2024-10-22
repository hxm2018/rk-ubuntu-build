#!/bin/bash
work_path=$(dirname $(readlink -f $0))
sh ${work_path}/stop.sh
sh ${work_path}/start.sh
echo '重启成功!'