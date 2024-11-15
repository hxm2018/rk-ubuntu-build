lanac=/opt/probe/sensor/lanac
update=/opt/probe/sensor/update
watchdog=/opt/probe/sensor/watchdog

# 启动lanac主进程
echo "Starting $lanac"
$lanac -v
if [ ! -f $lanac ];then
    sleep 5
    echo "Info: No $lanac"
else
    $lanac -d
fi

echo "Starting $update"
$update -v
if [ ! -f $update ];then
    echo "Info: No $update"
else
    $update -d
fi


echo "Starting $watchdog"
$watchdog -v
if [ ! -f $watchdog ];then
    echo "Info: No $watchdog"
else
    $watchdog -d
fi