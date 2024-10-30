#!/bin/sh


if [ `df | grep /data|wc -l` -gt 0 ];then
   echo "/data already exist."
   exit 0
fi

DATA_DRIVER_EXIST="no"
DISK_SIZE_MAX_NAME=""
DISK_SIZE_MAX=0


if [ -e /dev/sda ]; then  #存在两个硬盘

   DATA_DRIVER_EXIST="yes"

   for file in `ls /dev/sd[a-z]`
    do
      DISK_SIZE=$(fdisk -l|grep "Disk $file"|grep -v GPT|cut -d " " -f 3-|cut -d "," -f 1 |cut -d " " -f 1 | awk '{print int($0)}')
      echo "$file: $DISK_SIZE G"
      if [ ${DISK_SIZE_MAX} -eq 0 ]; then
         DISK_SIZE_MAX=$DISK_SIZE;
	      DISK_SIZE_MAX_NAME=$file;
      elif [ ${DISK_SIZE} -gt ${DISK_SIZE_MAX} ]; then
         DISK_SIZE_MAX=$DISK_SIZE;
  	      DISK_SIZE_MAX_NAME=$file;
      fi
    done

fi
DATA_DRIVER=$DISK_SIZE_MAX_NAME;

if [ $DATA_DRIVER_EXIST = "yes" ]; then
    if [ ! -d /data ];then
       mkdir /data
    fi


    MDISK=$DATA_DRIVER"1"
    if [ -b $MDISK ];then
       echo "Mounting Data Driver: $MDISK"
       xfs_repair -L $MDISK
       mount -t xfs $MDISK /data
    else
       echo "Disk block not exist"$MDISK
       
    fi
fi

