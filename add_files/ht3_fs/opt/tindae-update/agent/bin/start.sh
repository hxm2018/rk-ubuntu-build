#!/bin/bash

export JRE_HOME=/usr/local/jre
export PATH=$JRE_HOME/bin:$PATH

work_path=$(dirname $(readlink -f $0))
# jar包名称
process_name="tindae-update-agent.jar"
# gc日志路径
log_dir="/data/logs/tindae-update/agent/"

if [ ! -d "${log_dir}" ]; then
  mkdir -p "${log_dir}"
fi


pids=$(ps -ef | grep java | grep "$process_name" | awk '{print $2}')
if [ -n "$pids" ]; then
  echo "[$process_name]:已运行,pid:[$pids]"
  exit 1
fi

java_opt="-Xms256m -Xmx512m -Xmn512m -Xloggc:${log_dir}"$process_name"_gc.log -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=100M"
java_opt="${java_opt} -Djava.security.egd=file:/dev/./urandom"
java_opt="${java_opt} -jar ${work_path}/../${process_name}"


echo "正在启动[$process_name]..."
nohup java $java_opt > /dev/null 2>&1 &

count=0
while [ $count -lt 1 ]; do
  echo -e ".\c"
  sleep 1
  count=$(ps -ef | grep java | grep "$process_name" | awk '{print $2}' | wc -l)
  if [ "$count" -gt 0 ]; then
    break
  fi
done
pids=$(ps -ef | grep java | grep "$process_name" | awk '{print $2}')
echo "[$process_name]启动成功,pid：[$pids]"

