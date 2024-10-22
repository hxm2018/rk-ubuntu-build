#!/bin/bash

process_name="tindae-update-server.jar"
echo "stop[$process_name]......"

pids=$(ps -ef | grep java | grep "$process_name" | awk '{print $2}')
if [ -z "$pids" ]; then
  echo "停止失败,[$process_name]进程不存在"
  exit 1
fi

echo -e "停止[$process_name] ...\c"
for pid in $pids; do
  kill "$pid" >/dev/null 2>&1
done

count=0
while [ $count -lt 1 ]; do
  echo -e ".\c"
  sleep 1
  count=1
  for pid in $pids; do
    pid_exist=$(ps -f -p "$pid" | grep java)
    if [ -n "$pid_exist" ]; then
      count=0
      break
    fi
  done
done

echo "停止成功 pid：[$pids]"
