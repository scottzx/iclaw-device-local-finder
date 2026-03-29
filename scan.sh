#!/bin/bash
#
# iClaw 本地设备发现脚本
# 直接 curl 扫描 8080 端口，验证 openclaw 设备
#
# 用法:
#   ./scan.sh              # 自动检测本机 IP 并扫描
#   ./scan.sh 10.100.70   # 指定网段扫描
#

set -e

# 获取本机 IP
get_local_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "")
    if [[ -z "$ip" ]]; then
        echo "Error: Cannot determine local IP" >&2
        exit 1
    fi
    echo "$ip"
}

# 扫描单个 IP
scan_ip() {
    local ip=$1
    local response
    response=$(curl -s --connect-timeout 1 -m 2 "http://${ip}:8080/api/service/status" 2>/dev/null || echo "")

    if [[ -n "$response" ]]; then
        local port
        port=$(echo "$response" | jq -r '.port // empty' 2>/dev/null || echo "")
        if [[ "$port" == "18789" ]]; then
            local hostname
            hostname=$(echo "$response" | jq -r '.hostname // empty' 2>/dev/null || echo "$ip")
            echo "{\"ip\":\"$ip\",\"hostname\":\"$hostname\",\"port\":$port}"
        fi
    fi
}

# 主扫描逻辑
main() {
    local subnet="$1"

    if [[ -z "$subnet" ]]; then
        local local_ip
        local_ip=$(get_local_ip)
        echo "Local IP: $local_ip" >&2
        subnet="${local_ip%.*}"
    fi

    echo "Scanning subnet: $subnet.x" >&2

    local pids=()
    local results=()

    for i in $(seq 1 254); do
        local ip="${subnet}.${i}"
        (
            result=$(scan_ip "$ip")
            if [[ -n "$result" ]]; then
                echo "FOUND:$result"
            fi
        ) &
        pids+=($!)

        # 控制并发 50
        if (( ${#pids[@]} >= 50 )); then
            for pid in "${pids[@]}"; do
                wait $pid 2>/dev/null || true
            done
            pids=()
        fi
    done

    # 等待剩余
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
}

# 收集结果
main "$@" | grep "^FOUND:" | sed 's/^FOUND://' | jq -s '.'
