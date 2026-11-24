# 设备注册中心（iClaw Device Registry）

这是与 `scripts/register-device.sh` 配套的**服务端**。设备端脚本把本机信息（序列号、MAC、局域网 IP 列表、系统/内核/内存/磁盘等）POST 到注册中心；注册中心落盘保存，并提供一个网页按 serial 查看。

之所以放在本仓库：客户端协议（`POST /api/register`、`GET /health`、`/device-registry?serial=xxx`）由 `scripts/register-device.sh` 定义，服务端与它一一对应，同仓维护避免协议漂移。

## 协议

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/register` | 设备上报。Body 为 JSON：`{mac,serial,ip,ips,hostname,os,arch,kernel,uptime,memory,disk,cpu}`。`serial` 必填（不能是 `unknown`），成功返回 `200 {"ok":true,...}` |
| `GET` | `/health` | 返回 `{"status":"ok"}` |
| `GET` | `/?serial=XXX` | 单台设备详情网页 |
| `GET` | `/?serial=XXX&json=1` | 单台设备详情 JSON |
| `GET` | `/?all=1` | 全部设备 JSON |

`ip` / `ips` 在网页上合并为一行展示，每个 IP 带独立的一键复制按钮。

数据落盘在 `REGISTRY_DATA_DIR`（默认 `/var/lib/iclaw/registry`）下的 `devices.json`，原子写入，不依赖任何第三方库（Python 3 标准库即可）。

## 部署

目标机是一台公网 Linux（示例 `49.235.24.95` / `www.dreammate.work`）。

```bash
# 1. 放置代码
install -d -m 0755 /opt/device-registry /var/lib/iclaw/registry
install -m 0644 registry/server.py /opt/device-registry/server.py

# 2. systemd 服务
install -m 0644 registry/device-registry.service /etc/systemd/system/device-registry.service
systemctl daemon-reload
systemctl enable --now device-registry
systemctl is-active device-registry      # -> active

# 3. nginx 反代：把 registry/nginx-locations.conf 里的三个 location
#    放进 www.dreammate.work 的 443 server 块，然后：
nginx -t && systemctl reload nginx
```

自检：

```bash
curl -s https://www.dreammate.work/health
curl -s -X POST https://www.dreammate.work/api/register \
  -H 'Content-Type: application/json' \
  -d '{"serial":"SELFTEST","ip":"127.0.0.1","ips":["127.0.0.1"],"hostname":"selftest"}'
curl -s 'https://www.dreammate.work/device-registry?serial=SELFTEST'
```

## 客户端

设备端安装与定时任务见 `scripts/register-device.sh`：开机/每天由 systemd timer 触发，先等网络就绪（`GET /health`），再上报。它同时会把当前局域网 IP 写进 `/root/.openclaw/openclaw.json` 的 `gateway.controlUi.allowedOrigins`。
