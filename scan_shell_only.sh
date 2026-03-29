#!/bin/bash
#
# iClaw 设备发现脚本 (纯 Bash，无依赖)
# 扫描局域网发现 openclaw 设备
#
# 用法:
#   ./scan_shell_only.sh              # 自动检测本机 IP 并扫描
#   ./scan_shell_only.sh 10.100.70   # 指定网段扫描
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

# 从 JSON 中提取字段值（纯 bash，无 jq）
json_get() {
    local json="$1"
    local field="$2"
    echo "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# 扫描单个 IP
scan_ip() {
    local ip=$1
    local response
    response=$(curl -s --connect-timeout 1 -m 2 "http://${ip}:8080/api/deviceinfo" 2>/dev/null || echo "")

    if [[ -n "$response" ]]; then
        local serial hostname device_ip
        serial=$(json_get "$response" "serial")
        hostname=$(json_get "$response" "hostname")
        device_ip=$(json_get "$response" "ip")

        if [[ -n "$serial" && "$serial" != "null" ]]; then
            echo "${ip}|${hostname}|${serial}|${device_ip}"
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
    for i in $(seq 1 254); do
        local ip="${subnet}.${i}"
        (
            result=$(scan_ip "$ip")
            if [[ -n "$result" ]]; then
                echo "FOUND:$result"
            fi
        ) &
        pids+=($!)

        if (( ${#pids[@]} >= 50 )); then
            for pid in "${pids[@]}"; do
                wait $pid 2>/dev/null || true
            done
            pids=()
        fi
    done

    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
}

# 收集结果并转换为 JSON
main "$@" | grep "^FOUND:" | while IFS='|' read -r ip hostname serial device_ip; do
    echo "{\"ip\":\"$device_ip\",\"hostname\":\"$hostname\",\"serial\":\"$serial\"}"
done | {
    echo "["
    first=true
    while read -r line; do
        if [[ -n "$line" ]]; then
            $first && first=false || echo ","
            echo -n "$line"
        fi
    done
    echo ""
    echo "]"
}
