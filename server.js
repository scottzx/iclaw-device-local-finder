#!/usr/bin/env node
/**
 * iClaw 本地设备发现服务器
 * 提供 Web 界面展示扫描结果和收藏设备
 */

import express from 'express';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, 'data');
const FAVORITES_FILE = path.join(DATA_DIR, 'favorites.json');
const PORT = process.env.PORT || 3030;

// 确保 data 目录存在
if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 加载收藏
function loadFavorites() {
    try {
        if (fs.existsSync(FAVORITES_FILE)) {
            return JSON.parse(fs.readFileSync(FAVORITES_FILE, 'utf8'));
        }
    } catch (e) {}
    return [];
}

// 保存收藏
function saveFavorites(favorites) {
    fs.writeFileSync(FAVORITES_FILE, JSON.stringify(favorites, null, 2));
}

const app = express();

app.use(express.json());

// 静态文件
app.use(express.static(path.join(__dirname, 'public')));

// API: 获取收藏
app.get('/api/favorites', (req, res) => {
    res.json({ success: true, data: loadFavorites() });
});

// API: 添加收藏
app.post('/api/favorites', (req, res) => {
    const { mac, hostname, ip, openclaw_version } = req.body;

    if (!mac) {
        return res.status(400).json({ success: false, error: 'mac is required' });
    }

    const favorites = loadFavorites();
    const exists = favorites.find(f => f.mac === mac);

    if (!exists) {
        favorites.push({
            mac,
            hostname: hostname || ip,
            ip,
            openclaw_version,
            addedAt: new Date().toISOString()
        });
        saveFavorites(favorites);
    }

    res.json({ success: true, data: favorites });
});

// API: 移除收藏
app.delete('/api/favorites/:mac', (req, res) => {
    const { mac } = req.params;
    let favorites = loadFavorites();
    favorites = favorites.filter(f => f.mac !== mac);
    saveFavorites(favorites);
    res.json({ success: true, data: favorites });
});

// API: 执行扫描
app.get('/api/scan', async (req, res) => {
    const scriptPath = path.join(__dirname, 'scan.sh');
    const { subnet } = req.query; // 可选：指定网段

    if (!fs.existsSync(scriptPath)) {
        return res.status(500).json({ success: false, error: 'scan.sh not found' });
    }

    const args = subnet ? [subnet] : [];
    try {
        const result = await new Promise((resolve, reject) => {
            const proc = spawn('bash', [scriptPath, ...args], { timeout: 120000 });

            let stdout = '';
            let stderr = '';

            proc.stdout.on('data', (data) => { stdout += data.toString(); });
            proc.stderr.on('data', (data) => { stderr += data.toString(); });

            proc.on('close', (code) => {
                if (code === 0) {
                    resolve(stdout);
                } else {
                    reject(new Error(`scan.sh exited with code ${code}: ${stderr}`));
                }
            });

            proc.on('error', reject);
        });

        let devices = [];
        try {
            devices = JSON.parse(result);
        } catch (e) {
            // 空结果
        }

        res.json({ success: true, data: devices });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`iClaw Device Finder running at http://localhost:${PORT}`);
});
