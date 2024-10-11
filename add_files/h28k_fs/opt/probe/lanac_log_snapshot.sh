#!/bin/bash
# 生成日报数据库快照


# 访控模块
LANAC_LOG=/data/logs/lanac/


# 最大保存天数-优先从配置文件读取
# CFG_FILE_MAX=/opt/cbox/save_days
MAX_DAY=30

# if [ -f $CFG_FILE_MAX ] ; then
#   # 转换为数字（整型）
#   MAX_DAY=$((`cat $CFG_FILE_MAX`))
# fi

# 日志路径
OUTPUT=/tmp/lanac_log_snapshot_cron_run.log
#OUTPUT= /dev/null

if ! test -f $OUTPUT; then 
  touch $OUTPUT; 
fi

# 文件过大自动清空 > 4M
if [ `ls -s $OUTPUT |awk '{print $1}'` -gt 8192 ]; then
  echo "-----------------------------------------------------" > $OUTPUT;
  echo "Clear `date`" >> $OUTPUT;
  echo "-----------------------------------------------------" >> $OUTPUT;
fi

echo "" >> $OUTPUT;
echo "-----------------------------------------------------------" >> $OUTPUT;
echo "Log Snapshot Running `date` MaxDays: $MAX_DAY" >> $OUTPUT


# 23:59 执行，获取前一天的生成快照
#TODAY=`date -d 'yesterday' +%Y-%02m-%02d`
TODAY=`date -d 'today' +%Y-%02m-%02d`
echo "Today: $TODAY" >> $OUTPUT

cd $LANAC_LOG/
# 创建临时目录，拷贝日志文件到临时目录
mkdir $TODAY
echo "mv -f lanac.log.* $TODAY/" >> $OUTPUT
mv -f lanac.log.* $TODAY/
cp -f lanac.log $TODAY/

# 压缩日志文件，按日期保存
echo "tar -cjvf lanac-$TODAY.tar.bz2 $TODAY" >> $OUTPUT
tar -cjvf lanac-$TODAY.tar.bz2 $TODAY

# 清理临时目录
rm -rf $TODAY

# 获取当前时间
current_time=$(date +%s)
#echo "Now: $current_time"

# 遍历目录下的所有文件
# for file in $LANAC_LOG/lan*

# echo "find $LANAC_LOG -name lansensor-* -mtime +$MAX_DAY -delete"
# find $LANAC_LOG -name lansensor-* -mtime +$MAX_DAY -delete
# echo "done"
# exit

expiered_file1=`find $LANAC_LOG/ -name "lanac-*" -mtime +$MAX_DAY`
for file in $expiered_file1
do
  # 判断是否为文件
  if [ -n "$file" ]; then
    echo "Remove > $MAX_DAY days: $file " >> $OUTPUT
    rm $file -f
  fi
done

# for file in $LANAC_LOG/lansensor-*
# do
#   # 判断是否为文件
#   if [[ -f $file ]]; then
#     # 获取文件的修改时间
#     file_time=$(stat -c %Y "$file")
#     # 计算文件的存在时间
#     exist_time=$(expr $current_time - $file_time)
#     exist_days=$(expr $exist_time / 86400)

#     # 判断是否过期
#     if [[ $exist_days -gt $MAX_DAY ]]; then
#       # 删除文件
#       echo "删除文件：$file" >> $OUTPUT
#       rm -rf "$file"
#     fi
#   fi
# done

# 删除MAX_DAY天之前数据库文件
# expiered_file1=`find $LANAC_LOG/ -name lansensor-* -mtime +$MAX_DAY`
# if [ -n "$expiered_file1" ]; then
#   echo "Remove > $MAX_DAY days: $expiered_file1 " >> $OUTPUT
#   rm $expiered_file1 -f
# fi
