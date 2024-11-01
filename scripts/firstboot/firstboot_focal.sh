#!/bin/bash

FIRSTBOOT=firstboot.service

function get_root_partition_name() {
	local root_ptname=$(df / | tail -n1 | awk '{print $1}' | awk -F '/' '{print $3}')
	if [ "$root_ptname" == "" ];then
    		echo "找不到根文件系统对应的分区!"
    		destory_myself
    		exit 1
	fi
	echo $root_ptname
}

function get_root_disk_name() {
	local root_ptname=$(get_root_partition_name)
	local disk_name
	case $root_ptname in 
		mmcblk?p[1-4]) disk_name=$(echo $root_ptname | awk '{print substr($1, 1, length($1)-2)}');;
		    nvme?n?p?) disk_name=$(echo $root_ptname | awk '{print substr($1, 1, length($1)-2)}');;
	    [hsv]d[a-z][1-9]*) disk_name=$(echo $root_ptname | awk '{print substr($1, 1, length($1)-1)}');;
		            *) echo "无法识别 $root_ptname 的磁盘类型!"
			       exit 1
			       ;;
	esac
	echo "$disk_name"
}

function fix_partition() {
	local disk_name=$(get_root_disk_name)
	# 第一次运行，需要修复磁盘大小
	echo "fix partiton ... "
	printf 'f\n' | parted ---pretend-input-tty /dev/${disk_name} unit Mib print || fail=1
	if [ "$fail" == "1" ];then
		echo "分区表未修复！需要手动执行 $MYSELF"
		exit 1
	fi
	echo "done"
	echo
}

function check_partition_count() {
	local disk_name=$(get_root_disk_name)
	local current_pt_cnt=$(parted -s /dev/${disk_name} print | awk '$1~/[1-9]+/ {print $1}' | wc -l)
	if [ "$current_pt_cnt" != "2" ];then
    		echo "现存分区数量不为2,放弃!"
        	exit 1
	fi
	echo "Current partition count is valid: $current_pt_cnt"
}

function resize_partition() {
	local disk_name=$(get_root_disk_name)
	echo "resize partition /dev/${disk_name} ... "
	printf 'Yes\n-1\n' | parted ---pretend-input-tty /dev/${disk_name} resizepart 2 100%
	if [ $? -ne 0 ];then
		echo "分区扩展失败!"
		exit 1
	fi
	echo "done"
	echo
}

function resize_filesystem() {
	local part_name=$(get_root_partition_name)
	local fstype=$(df -T / | tail -n1 | awk '{print $2}')
	echo "resize / at /dev/${part_name} ... "
	case $fstype in 
		btrfs) btrfs filesystem resize max /
		       ;;
		 ext4) resize2fs /dev/${part_name}
		       ;;
		  xfs) xfs_growfs -d /
		       ;;
	esac
	echo "done"
	echo 
}

function daemon_reload() {
	echo "systemctl daemon-reload ... "
	systemctl daemon-reload
	echo "done"
	echo
}

function enable_service() {
	echo "disable service $1 ... "
	systemctl enable $1
	echo "done"
	echo
}

function start_service() {
	echo "start service $1 ... "
	systemctl start $1
	echo "done"
	echo
}

function stop_service() {
	echo "stop service $1 ... "
	systemctl stop $1
	echo "done"
	echo
}

function status_service() {
	echo "status of service $1 ... "
	systemctl status $1
	echo "done"
	echo
}

function restart_service() {
	echo "restart service $1 ... "
	systemctl restart $1
	echo "done"
	echo
}


function disable_service() {
	echo "disable service $1 ... "
	systemctl disable $1
	echo "done"
	echo
}

function setup_hostname() {
	local conf="/etc/firstboot_hostname"
	if [ -f $conf ];then
		hostname=$(cat $conf)
		if [ "$hostname" != "" ];then
			hostnamectl set-hostname $hostname
		fi
		rm -f $conf
	fi

}

function reset_machine_id() {
	local conf="/etc/firstboot_machine_id.conf"
	if [ -f $conf ];then
		source $conf
		if [ "$RESET_MACHINE_ID" == "yes" ];then
			echo "resetting machine id ... "
			rm -f /etc/machine-id
			rm -rf /var/log/journal/*
			systemd-machine-id-setup
			echo "done"
		fi
		rm -f $conf
	fi

}

function get_ifnames() {
	(
		cd /sys/class/net
		local eths=$(ls -d eth* 2>/dev/null)
		local ens=$(ls -d en* 2>/dev/null)
		echo "$eths $ens"
	)
}

function write_yml_head() {
	local yml=$1
	local renderer=$2
	if [ "$renderer" == "networkd" ];then
		cat > $yml <<EOF
network:
  version: 2
  renderer: $renderer
  ethernets:
EOF
	else
		cat > $yml <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
	fi
}

function write_yml_ifname() {
	local yml=$1
	local ifname=$2
	cat >> $yml <<EOF
    $ifname:
EOF
}

function write_yml_dhcp() {
	local yml=$1
	local dhcp_switch=$2
	cat >> $yml <<EOF
      dhcp4: $dhcp_switch
      dhcp6: $dhcp_switch
EOF
}

function write_yml_ipaddr() {
	local yml=$1
	local ips=$2
	cat >> $yml <<EOF
      addresses: [$ips]
EOF
}

function write_yml_routes() {
	local yml=$1
	local routes=$2
	cat >> $yml <<EOF
      routes:
EOF
	for to_via in "$routes";do
		to=$(echo $to_via | awk -F ':' '{print $1}')
		via=$(echo $to_via | awk -F ':' '{print $2}')
		cat >> $yml <<EOF
        - to: $to
          via: $via
EOF
	done
}

function write_yml_dns() {
	local yml=$1
	local dns=$2
	local search_domain=$3
	cat >> $yml <<EOF
      nameservers:
        addresses: [$DNS]
EOF
	if [ "$search_domain" != "" ];then
		cat >> $yml <<EOF
        search: [$search_domain]
EOF
	fi
}

function write_yml_link_local() {
	local yml=$1
	local link_local=$2
	cat >> $yml <<EOF
      link-local: []
EOF
}

function create_netplan_config() {
	local renderer=$1
	local yml="/etc/netplan/00-default-config.yaml"
	shift
	local if_idx
	local ips
	local routes
	local link_local

	write_yml_head "$yml" "$renderer"
	# networkd
	if [ "$renderer" == "networkd" ];then
		if_idx=1
		while [ "$1" != "" ];do
			# get variables
			case $if_idx in
				1) ips=$IF1_IPS
				   routes=$IF1_ROUTES
				   link_local=$IF1_LINK_LOCAL
				   ;;
				2) ips=$IF2_IPS
				   routes=$IF2_ROUTES
				   link_local=$IF2_LINK_LOCAL
				   ;;
				3) ips=$IF3_IPS
				   routes=$IF3_ROUTES
				   link_local=$IF3_LINK_LOCAL
				   ;;
				4) ips=$IF4_IPS
				   routes=$IF4_ROUTES
				   link_local=$IF4_LINK_LOCAL
				   ;;
				*) ips=""
				   routes=""
				   ;;
			esac # end get variables

			# ip address
			case $ips in
				dhcp)	write_yml_ifname "$yml" "$1"
					write_yml_dhcp "$yml" "true"
					write_yml_link_local "$yml" "$link_local"
					;;
				  '')	echo "$1 do nothing";;
				   *)	write_yml_ifname "$yml" "$1"
					write_yml_dhcp "$yml" "false"
					write_yml_ipaddr "$yml" "$ips"
					write_yml_link_local "$yml" "$link_local"
					# routes
					if [ "$routes" != "" ];then
						write_yml_routes "$yml" "$routes"
					fi # end routes
					# dns
					if [ "$DNS" != "" ];then
						write_yml_dns "$yml" "$DNS" "$SEARCH_DOMAIN"
					fi
					;;
			esac # end ip addr

			# next ifname
			shift
			let if_idx++
		done
	fi #networkd
	chmod 600 $yml
	echo 'done'
	echo
}

function write_eth_config() {
	local eth="$1$2"
	case $2 in
		eth0)
			echo "$eth"
			cat >> $eth <<EOF
auto eth0
iface eth0 inet static
	address 0.0.0.0
post-up sysctl -w net.ipv6.conf.eth0.disable_ipv6=1
EOF
		;;
		eth1)
			echo "$eth"
			cat >> $eth <<EOF
auto eth1
iface eth1 inet static
	address 192.168.8.8
	netmask 255.255.255.0
post-up sysctl -w net.ipv6.conf.eth1.disable_ipv6=1
EOF
		;;
	esac

}


function creat_ifupdown_config() {
	local path="/etc/network/interfaces.d/"	
	echo "$1"
	shift
	echo "$1"
	while [ "$1" != "" ];do
		write_eth_config $path $1
		shift
		echo "$1"
	done
	echo 'done'
	echo	
}

function config_network() {
	local conf="/etc/firstboot_network.conf"
	if [ -f $conf ];then
		source $conf
	fi

	local ifnames=$(get_ifnames)
	if [ "$ifnames" != "" ];then
		[ -z "${NETPLAN_BACKEND}" ] && NETPLAN_BACKEND="ifupdown"
		case ${NETPLAN_BACKEND} in
			NetworkManager)	# netplan with NetworkManager
					create_netplan_config ${NETPLAN_BACKEND} $ifnames
					stop_service NetworkManager.service
					stop_service systemd-networkd.service
					disable_service systemd-networkd.service
					enable_service NetworkManager.service
					start_service NetworkManager.service
					netplan apply
					;;
			networkd)	# netplan with networkd
					create_netplan_config ${NETPLAN_BACKEND} $ifnames
					stop_service NetworkManager.service
					stop_service systemd-networkd.service
					disable_service NetworkManager.service
					enable_service systemd-networkd.service
					start_service systemd-networkd.service
					netplan apply
					;;
			ifupdown*)	# ifupdown or ifupdown2
					creat_ifupdown_config ${NETPLAN_BACKEND} $ifnames
					stop_service systemd-networkd.service
					disable_service systemd-networkd.service
					enable_service networking.service
					restart_service networking.service
					;;
		esac
	fi

}

function disable_suspend() {
	systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
}

function clean_logs() {
	find /var/log -name '*log*' -type f -exec rm {} \;
}

function clean_debootstrap_dir() {
	rm -rf /debootstrap
}

function enable_rknpu() {
	if modinfo rknpu 2>/dev/null;then
		echo rknpu > /etc/modules-load.d/rknpu.conf
		echo "alias rknpu rknpu" > /etc/modprobe.d/rknpu.conf
		modprobe rknpu
		if [ -f "/usr/local/lib/systemd/system/rknn.service" ];then
			ldconfig
			systemctl enable rknn.service
			systemctl start rknn.service
		fi
	fi
}

function set_lightdm_default_xsession() {
	local installed=$(dpkg -l lightdm | tail -n1 | awk '{print $1}')
	if [ "$installed" != "ii" ];then
		echo "lightdm is not installed"
		return
	fi

	if [ "$1" == "xfce" ];then
		cat > /usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf <<EOF
[Seat:*]
user-session=xfce
EOF
	elif [ "$1" == "ubuntu" ];then
		cat > /usr/share/lightdm/lightdm.conf.d/50-ubuntu.conf <<EOF
[Seat:*]
user-session=ubuntu
EOF
	fi
	stop_service lightdm.service
	start_service lightdm.service
}

function reset_sshd_key() {
	local switch=$1
	if [ "$switch" == "yes" ];then
		echo "Reset openssh keys ..."
		rm -f /etc/ssh/ssh_host_*key*
		DEBIAN_FRONTEND=noninteractive dpkg-reconfigure openssh-server
		echo "done"
	fi
}

function change_sshd_port() {
	local port=$1
	local conf=/etc/ssh/sshd_config
	if [ "$port" != "" ] && [ $port -ge 1 ] && [ $port -le 65535 ];then
		echo "Change sshd port to $port"
		sed -e '/^Port/d' -i $conf || echo "Change $conf failed! [$port]"
		echo "Port $port" | tee -a $conf
		echo "done"
	fi
}

function change_sshd_permit_root_login() {
	local var=$1
	local conf=/etc/ssh/sshd_config
	if [ "$var" != "" ];then
		case $var in
			prohibit-password|forced-commands-only|yes|no)
				echo "Change PermitRootLogin to $var"
				sed -e '/^PermitRootLogin/d' -i $conf || echo "Change $conf failed! [$var]"
				echo "PermitRootLogin ${var}" | tee -a $conf
				echo "done"
				;;
			*)	echo "Illegal parameter value: $var"
				;;
		esac
	fi
}

function change_sshd_ciphers() {
	local ciphers=$1
	local conf=/etc/ssh/sshd_config

	if [ "$ciphers" != "" ];then
		echo "Change sshd ciphers to $ciphers"
		sed -e '/^Ciphers/d' -i $conf || echo "Change $conf failed! [$ciphers]"
		echo "Ciphers $ciphers" | tee -a $conf
		echo "done"
	fi
}

function change_ssh_ciphers() {
	local ciphers=$1
	local conf=/etc/ssh/ssh_config

	if [ "$ciphers" != "" ];then
		echo "Change ssh ciphers to $ciphers"
		sed -e '/^    Ciphers/d' -i $conf || echo "Change $conf failed! [$ciphers]"
		echo "    Ciphers $ciphers" | tee -a $conf
		echo "done"
	fi
}

function  change_ssh_key_types () {
	local key_type=$1
	local conf=/etc/ssh/sshd_config
	if [ "$key_type" != "" ];then
		echo "Change sshd key type to $key_type"
		sed -e '/^PubkeyAcceptedKeyTypes/d' -i $conf || echo "Change $conf failed! [$key_type]"
		echo "PubkeyAcceptedKeyTypes=$key_type" | tee -a $conf
		echo "done"
	fi	
}

function config_openssh_server() {
	local conf="/etc/firstboot_openssh.conf"
	stop_service "ssh.service"
	if [ -f $conf ];then
		source  $conf
		change_sshd_port "$SSHD_PORT"
		change_sshd_permit_root_login "$SSHD_PERMIT_ROOT_LOGIN"
		change_sshd_ciphers "$SSHD_CIPHERS"
		change_ssh_ciphers "$SSH_CIPHERS"
		reset_sshd_key "$RESET_SSH_KEYS"
		change_ssh_key_types "$PUBKEY_ACCEPTEDKEY_TYPES"
		rm -f $conf
	fi
	enable_service "ssh.service"
	start_service "ssh.service"

}

function config_i18n() {
	local conf="/etc/firstboot_i18n.conf"
	if [ -f $conf ];then
		source $conf
		if [ -n "${LANGUAGE}" ];then
			echo "Change default language to ${LANGUAGE}"
			update-locale LANG=${LANGUAGE} && update-locale LC_ALL=${LANGUAGE} && \
				echo "done" || \
				echo "failed"
		fi

		if [ -n "${TIMEZONE}" ];then
			if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ];then
				echo "Change default time zone to ${TIMEZONE}"
				ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
				dpkg-reconfigure -f noninteractive tzdata && echo "done" || echo "failed"
			else
				echo "Time zone [${TIMEZONE}] does not exists!"
			fi
		fi

		rm -f $conf
	fi

}

function restart_getty() {
	local i=1
	while [ $i -le 12 ];do
		local enabled=$(systemctl is-enabled getty@tty${i}.service)
		if [ "$enabled" == "enabled" ];then
			echo "restart getty@tty${i}.service"
			restart_service "getty@tty${i}.service"
		fi
		let i++
	done
}

function modify_user_pswd() {
	local file="/etc/user_pswd"
	if [ -f ${file} ];then
		ups=$(cat ${file})
		for up in ${ups};do
			u=$(echo ${up} | awk -F ':' '{print $1}')
			p=$(echo ${up} | awk -F ':' '{print $2}')
			g=$(echo ${up} | awk -F ':' '{print $3}')
			G=$(echo ${up} | awk -F ':' '{print $4}')

			# create new user if not exists
			if ! grep -e "^${u}:" /etc/passwd;then
				echo "create group ${g} ..."
				groupadd ${g}
				echo "create user ${u} ..."
				if [ -n "$G" ];then
					useradd -d /home/${u} -m -g ${g} -G ${G} -s /bin/bash ${u}
				else
					useradd -d /home/${u} -m -g ${g} -s /bin/bash ${u}
				fi
			fi

			# setup default password for user
			echo -n "change user ${u}'s password ..."
			if echo "${u}:${p}" | /usr/sbin/chpasswd -c SHA512; then
				echo "succeed"
			else
				echo "failed"
			fi
		done
		rm -f ${file}
		#restart_getty
	fi

}

function lanac_log_snapshot() {
	echo "59 23 * * * root /bin/bash /opt/probe/lanac_log_snapshot.sh" >> /etc/crontab

}

function jdk_path() {
	echo "config jdk path ...."
	ln -s /usr/local/jdk1.8.0_361 /usr/local/jre
	chmod +R 755 /usr/local/jre
	local profile="/etc/profile"
	local jre_home="/usr/local/jre"
	cat >> $profile <<EOF
ulimit -n 8192
export JRE_HOME=/usr/local/jre
export PATH=$jre_home/bin:\$PATH
EOF
	source $profile 
}

function write_yml_link_local() {
	local yml=$1
	local link_local=$2
	cat >> $yml <<EOF
      link-local: []
EOF
}

function link_bash_sh() {
	ln -sf /bin/bash /usr/bin/sh
}

function mkfs_xfs_disk() {
	local disk_size
	for file in `ls /dev/sd[a-z]`;do
			disk_size=$(fdisk -l | grep "Disk /dev/sda" | grep -v GPT | cut -d " " -f 3-|cut -d "," -f 1|cut -d " " -f 1| awk '{print int($0)}')
			if [ $disk_size -gt 0 ]; then
				for file in `ls /dev/sd[a-z]`;do
						umount $file > /dev/null 2>&1
						for num in `parted $file print | grep -E '^\s+[0-9]+' | awk '{print $1}'`;do
								umount $file$num > /dev/null 2>&1
								parted $file rm $num
								echo "rm" $file$num
						done

						sleep 2
						echo "mkfs.xfs "$file "......"  
						parted -s $file mklabel gpt
						parted -s $file mkpart primary xfs 0% 100%
						mkfs.xfs -f $file'1'
				done
			fi
	done
}

fix_partition
check_partition_count
resize_partition
resize_filesystem
sleep 5

setup_hostname
reset_machine_id
config_network
config_openssh_server
config_i18n
disable_suspend

clean_logs
clean_debootstrap_dir

modify_user_pswd

set_lightdm_default_xsession "xfce"
enable_rknpu
jdk_path
mkfs_xfs_disk
link_bash_sh
sleep 1

if [ -f /usr/lib/systemd/system/ssd1306.service ];then
	enable_service ssd1306.service
	start_service ssd1306.service
fi

if [ -f /usr/lib/systemd/system/chrony.service ];then
	enable_service chrony.service
	start_service chrony.service
fi

if [ -f /usr/local/lib/systemd/system/rc-local.service ];then
	systemd daemon-reload
	enable_service rc-local.service
	start_service rc-local.service
	echo `date +%F" "%T` "run rc-local.service" >> /var/log/firstboot.log
	sleep 1
	#restart_service rc-local.service
	systemctl status rc-local.service
	if [ $? -ne 0 ];then
		echo `date +%F" "%T` "restart rc-local.service" >> /var/log/firstboot.log
	    stop_service rc-local.service
	    start_service rc-local.service
	fi
fi

sync

disable_service $FIRSTBOOT
