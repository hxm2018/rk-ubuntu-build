#!/bin/bash
# version: 5.2

# 检查参数数量
if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 <network_interface>" >&2
    exit 1
fi

# 获取网口名称
interface="$1"

# 配置文件位置
mac_prefix_config="/etc/mac_prefix.conf"
mac_address_config="/etc/mac_addresses.conf"

# 获取所有以 e 开头的物理以太网接口，按 ASCII 顺序排序
interfaces=($(for iface in /sys/class/net/*; do
    if [[ -e "$iface/type" && $(cat "$iface/type") -eq 1 && $(basename "$iface") == e* ]]; then
        basename "$iface"
    fi
done | sort))

# 验证输入的网口名称是否在 interfaces 数组中
if [[ ! " ${interfaces[@]} " =~ " ${interface} " ]]; then
    echo "Network interface $interface does not exist in the physical Ethernet interfaces." >&2
    exit 1
fi

# 定义 MAC 前缀
mac_prefixes="00:0e:8e
00:14:22
00:18:8c
00:1b:77
00:1d:92
00:20:18
00:4f:49
00:60:52
00:e0:4c
16:5b:22
52:54:ab
d4:3d:7f
f0:25:b7
28:6a:8d
b0:7b:d5
d8:0d:26"

# 读取 MAC 前缀
load_mac_prefixes() {
    if [[ -f "$mac_prefix_config" ]]; then
        mapfile -t mac_groups < "$mac_prefix_config"
    else
        # 将 MAC 前缀写入到配置文件中
        echo -e "$mac_prefixes" > "$mac_prefix_config"
        chmod 600 "$mac_prefix_config"  # 设置文件权限
        mapfile -t mac_groups < "$mac_prefix_config"
    fi
}

# 获取唯一 ID
get_unique_id() {
    cpu_sn=$(grep 'Serial' /proc/cpuinfo 2>/dev/null | awk '{print $3}' 2>/dev/null)

    if [[ -n "$cpu_sn" ]]; then
        serial="$cpu_sn"
    elif [[ -d /sys/block/mmcblk1 ]]; then
        serial=$(< /sys/block/mmcblk1/device/cid 2>/dev/null)
    elif [[ -d /sys/block/mmcblk0 ]]; then
        serial=$(< /sys/block/mmcblk0/device/cid 2>/dev/null)
    elif [[ -f /etc/machine-id ]]; then
        serial=$(< /etc/machine-id 2>/dev/null)
    else
        serial=$(od -An -N6 -tx1 /dev/random | tr -d ' \n')
    fi

    serial="${serial,,}"  # 转换为小写
    serial="${serial//0x/}"  # 去除前缀 "0x"

    # 对 serial 进行 SHA256 哈希
    echo "$(echo -n "$serial" | sha256sum | cut -f1)"
}

# 生成 MAC 地址
generate_mac() {
    load_mac_prefixes
    local mac_grp_count=${#mac_groups[@]}
    local unique_id=$(get_unique_id)
    local sum=0

    for (( i=0; i<${#unique_id}; i++ )); do
        hex_char="${unique_id:i:1}"
        hex_value=$(printf '%d' "0x$hex_char" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            sum=$(( sum + hex_value ))
        fi
    done

    local idx=$(( sum % mac_grp_count ))
    local mac_head=${mac_groups[$idx]}

    local fibonacci=(0 1 1 2 3 5 8 13 21 34 55)  # 有效的斐波那契数列
    local byte1_index=${fibonacci[3]} # 2
    local byte2_index=${fibonacci[5]} # 5
    local byte3_index=${fibonacci[8]} # 21

    if [[ ${#unique_id} -le $byte3_index ]]; then
        echo "Error: unique_id is too short." >&2
        exit 1
    fi

    local byte1="${unique_id:$byte1_index:2}"
    local byte2="${unique_id:$byte2_index:2}"
    local byte3="${unique_id:$byte3_index:2}"

    # 转换为小写
    byte1="${byte1,,}"
    byte2="${byte2,,}"
    byte3="${byte3,,}"

    local mac_tail="${byte1}:${byte2}:${byte3}"

    echo "${mac_head}:${mac_tail}"
}

# MAC 地址增减
mac_offset() {
    local mac_address="$1"
    local offset="$2"

    if [[ ! $mac_address =~ ^([0-9a-fA-F]{2}(:|-)){5}([0-9a-fA-F]{2})$ ]]; then
        echo "Invalid MAC address format." >&2
        return 1
    fi

    IFS=':' read -r b1 b2 b3 b4 b5 b6 <<< "$mac_address"
    local mac_dec=$(( (0x$b1 << 40) | (0x$b2 << 32) | (0x$b3 << 24) | (0x$b4 << 16) | (0x$b5 << 8) | (0x$b6) ))

    mac_dec=$(( mac_dec + offset ))

    local new_mac=$(printf "%02X:%02X:%02X:%02X:%02X:%02X" \
        $(( (mac_dec >> 40) & 0xFF )) \
        $(( (mac_dec >> 32) & 0xFF )) \
        $(( (mac_dec >> 24) & 0xFF )) \
        $(( (mac_dec >> 16) & 0xFF )) \
        $(( (mac_dec >> 8) & 0xFF )) \
        $(( mac_dec & 0xFF )))

    echo "${new_mac,,}"  # 转换为小写
}

# 检查配置文件，获取当前 MAC 地址
configured_mac_address=""
if [[ -f "$mac_address_config" ]]; then
    configured_mac_address=$(grep "^$interface " "$mac_address_config" | awk '{print $2}')

    # 检查 MAC 地址的合法性
    if [[ ! "$configured_mac_address" =~ ^([0-9a-fA-F]{2}(:|[-])?){5}[0-9a-fA-F]{2}$ ]]; then
        echo "Invalid MAC address found in config for $interface. Removing it."
        sed -i "/^$interface /d" "$mac_address_config"  # 从配置文件中删除这一行
        configured_mac_address=""
    fi
fi

# 生成完整的 MAC 地址如果配置文件中不存在当前 MAC 地址
if [[ -n "$configured_mac_address" ]]; then
    echo "Found MAC Address for $interface in config: $current_mac_address"
    final_mac_address=${configured_mac_address,,}
else
    # 生成完整的 MAC 地址
    final_mac_address=$(generate_mac)

    # 找到输入的网络接口的索引
    index=1
    for iface in "${interfaces[@]}"; do
        if [[ "$iface" == "$interface" ]]; then
            break
        fi
        index=$(( index + 1 ))
    done

    # 忽略空接口
    if (( index > 0 )); then
        offset=$(( index - 1 ))
        [[ $offset -gt 0 ]] && final_mac_address=$(mac_offset "$final_mac_address" "$offset")
    else
        echo "Interface $interface not found in the sorted list." >&2
        exit 1
    fi

    # 检查接口名及对应的 MAC 地址是否已经存在
    if ! grep -q "^$interface " "$mac_address_config"; then
        # 将接口名及对应的 MAC 地址写入配置文件
        echo "$interface $final_mac_address" >> "$mac_address_config"

        # 排序配置文件并输出到临时文件，然后替换原文件
        sort -u "$mac_address_config" -o "$mac_address_config"

        # 设置文件权限
        chmod 600 "$mac_address_config"  # 设置文件权限
    else
        echo "MAC Address for $interface already exists in the configuration file."
    fi
fi

# 获取当前接口的 MAC 地址并转换为小写
current_mac_address_sys=$(< "/sys/class/net/$interface/address")
current_mac_address_sys="${current_mac_address_sys,,}"

# 检查当前 MAC 地址是否与新设置的地址相同
if [[ "$current_mac_address_sys" == "$final_mac_address" ]]; then
    echo "MAC Address for $interface is already set to $final_mac_address. No changes made."
else
    echo "Resulting MAC Address for $interface: $final_mac_address"

    # 设置指定接口的 MAC 地址
    ip link set dev "$interface" down       # 先将接口关闭
    ip link set dev "$interface" address "$final_mac_address"  # 设置新的 MAC 地址
    ip link set dev "$interface" up         # 重新启用接口
    echo "MAC Address for $interface has been set to $final_mac_address."
fi
