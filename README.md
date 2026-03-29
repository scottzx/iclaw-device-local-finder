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

## 功能

- 扫描本地网络中的设备
- 收藏常用设备
- Web 界面展示扫描结果

## API

- `GET /api/scan` - 执行设备扫描
- `GET /api/favorites` - 获取收藏设备
- `POST /api/favorites` - 添加收藏设备
- `DELETE /api/favorites/:mac` - 移除收藏设备
