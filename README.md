# iClaw Device Local Finder

iClaw 本地设备发现工具，用于扫描和管理本地网络中的设备。

## 安装

```bash
npm install
```

## 运行

```bash
npm start
```

或使用 npx：

```bash
npx iclaw-device-local-finder
```

## 设备注册中心（服务端）

本仓库同时包含与 `scripts/register-device.sh` 配套的**服务端**，见 [`registry/`](registry/README.md)：设备把局域网 IP、序列号等上报到 `www.dreammate.work/api/register`，服务端落盘并提供 `device-registry?serial=xxx` 查询页。部署脚本、systemd 单元与 nginx 反代配置都在该目录下。

## 功能

- 扫描本地网络中的设备
- 收藏常用设备
- Web 界面展示扫描结果
- 设备自动上报局域网 IP（客户端脚本 + 服务端注册中心）

## API

- `GET /api/scan` - 执行设备扫描
- `GET /api/favorites` - 获取收藏设备
- `POST /api/favorites` - 添加收藏设备
- `DELETE /api/favorites/:mac` - 移除收藏设备
