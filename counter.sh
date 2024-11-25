#!/bin/bash

# 文件用于存储计数器和日期
DATA_FILE="counter_data.txt"
#echo $DATA_FILE
# 获取当前日期
current_date=$(date +%Y-%m-%d)

# 检查数据文件是否存在，如果不存在则创建并初始化
if [ ! -f "$DATA_FILE" ]; then
    echo "0 $current_date" > "$DATA_FILE"
    count=1
else
    # 读取数据文件中的计数器和日期
    read count last_date < "$DATA_FILE"

    # 检查日期是否变更
    if [ "$current_date" != "$last_date" ]; then
        count=1
    else
        count=$((count + 1))
    fi
fi

# 更新数据文件
echo "$count $current_date" > "$DATA_FILE"

# 输出当前计数
echo "当前日期: $current_date, 累加计数: $count"
