#!/usr/bin/env python3
"""iClaw device registry - receives device reports and serves the registry page.

Protocol (reverse engineered from iclaw-device-local-finder/scripts/register-device.sh):
  POST /api/register        <- {mac,serial,ip,ips,hostname,os,arch,kernel,uptime,memory,disk,cpu}
  GET  /health              -> {"status":"ok"}
  GET  /?serial=XXX         -> device info HTML page
  GET  /?serial=XXX&json=1  -> device info JSON
  GET  /?all=1              -> all devices JSON

nginx maps:
  location /api/          -> http://127.0.0.1:1420/api/
  location /health        -> http://127.0.0.1:1420/health
  location /device-registry -> http://127.0.0.1:1420/   (prefix stripped)
"""
import html
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

DATA_DIR = os.environ.get("REGISTRY_DATA_DIR", "/var/lib/iclaw/registry")
DATA_FILE = os.path.join(DATA_DIR, "devices.json")
os.makedirs(DATA_DIR, exist_ok=True)


def load_devices():
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_devices(devices):
    tmp = DATA_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(devices, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DATA_FILE)


FIELD_LABELS = {
    "serial": "序列号",
    "mac": "MAC 地址",
    "hostname": "主机名",
    "ip": "IP 地址",
    "ips": "IP 列表",
    "os": "操作系统",
    "arch": "架构",
    "kernel": "内核版本",
    "uptime": "运行时长",
    "memory": "内存",
    "disk": "磁盘",
    "cpu": "CPU",
    "lastSeen": "最后上报",
}


def _copy_button(text, label="复制"):
    """Small one-click copy button using Clipboard API with a textarea fallback."""
    value = html.escape(str(text), quote=True)
    return (
        f'<button class="copy" type="button" data-copy="{value}" '
        f'onclick="copyIp(this)">{label}</button>'
    )


def _ips_text(rec):
    """Plaintext representation of the device's IP address(es)."""
    ips = rec.get("ips") or ([rec.get("ip")] if rec.get("ip") else [])
    if isinstance(ips, (list, tuple)):
        return "\n".join(str(x) for x in ips)
    return str(ips)


def render_page(serial, devices):
    if serial:
        rec = devices.get(serial)
        title = f"设备 {html.escape(serial)}"
        if rec:
            rows = []
            for k, v in sorted(rec.items(), key=lambda kv: (kv[0] != "serial", kv[0])):
                if k == "ips":
                    # Merged into the single "IP 地址" row below.
                    continue
                if k == "ip":
                    # One combined row, with a dedicated copy button per IP.
                    seen = set()
                    cells = []
                    for one_ip in _ips_text(rec).splitlines():
                        if not one_ip or one_ip in seen:
                            continue
                        seen.add(one_ip)
                        cells.append(
                            f'<span class="ip-item"><code>{html.escape(one_ip)}</code>'
                            f'{_copy_button(one_ip)}</span>'
                        )
                    rows.append(
                        "<tr><th>IP 地址</th><td>" + " ".join(cells) + "</td></tr>"
                    )
                    continue
                shown = json.dumps(v, ensure_ascii=False) if isinstance(v, (list, dict)) else str(v)
                cell = html.escape(shown)
                rows.append(
                    f"<tr><th>{html.escape(FIELD_LABELS.get(k, k))}</th><td>{cell}</td></tr>"
                )
            body = (
                "<h1>iClaw 设备注册表</h1>"
                f"<h2>{title}</h2>"
                '<table>' + "".join(rows) + '</table>'
            )
        else:
            body = f"<h1>iClaw 设备注册表</h1><h2>{title}</h2><p class='warn'>尚未收到该设备的上报。</p>"
    else:
        rows = []
        for sn, rec in sorted(devices.items()):
            ips_text = _ips_text(rec)
            ips_html = html.escape(ips_text.replace("\n", ", "))
            rows.append(
                "<tr>"
                f"<td><a href='?serial={html.escape(sn)}'>{html.escape(sn)}</a></td>"
                f"<td>{html.escape(str(rec.get('hostname','')))}</td>"
                f"<td>{ips_html} {_copy_button(ips_text)}</td>"
                f"<td>{html.escape(str(rec.get('os','')))}</td>"
                f"<td>{html.escape(str(rec.get('lastSeen','')))}</td>"
                "</tr>"
            )
        body = (
            "<h1>iClaw 设备注册表</h1>"
            f"<p>共 {len(devices)} 台设备已上报。带 <code>?serial=xxx</code> 查看单台详情。</p>"
            "<table><tr><th>序列号</th><th>主机名</th><th>IP 地址</th><th>操作系统</th><th>最后上报</th></tr>"
            + "".join(rows) + "</table>"
        )

    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title if serial else 'iClaw 设备注册表'}</title>
<style>
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;max-width:960px;margin:32px auto;padding:0 16px;color:#1f2937}}
h1{{font-size:22px}} h2{{font-size:18px;margin-top:24px}}
table{{border-collapse:collapse;width:100%;margin-top:16px;font-size:14px}}
th,td{{border:1px solid #e5e7eb;padding:8px 12px;text-align:left;vertical-align:top}}
th{{background:#f9fafb;white-space:nowrap;width:160px}}
a{{color:#2563eb;text-decoration:none}} .warn{{color:#b45309}}
code{{background:#f3f4f6;padding:2px 6px;border-radius:4px}}
.ip-item{{display:inline-flex;align-items:center;white-space:nowrap;margin-right:14px;margin-bottom:4px}}
.copy{{margin-left:6px;padding:2px 8px;font-size:12px;cursor:pointer;border:1px solid #d1d5db;
background:#fff;color:#2563eb;border-radius:4px;line-height:1.4}}
.copy:hover{{background:#eff6ff;border-color:#93c5fd}}
.copy.done{{color:#059669;border-color:#a7f3d0;background:#ecfdf5}}
</style></head><body>{body}
<script>
function copyIp(btn){{
  var text = btn.getAttribute('data-copy') || '';
  function ok(){{
    var old = btn.getAttribute('data-label') || btn.textContent;
    btn.setAttribute('data-label', old);
    btn.textContent = '已复制';
    btn.classList.add('done');
    setTimeout(function(){{ btn.textContent = old; btn.classList.remove('done'); }}, 1500);
  }}
  if (navigator.clipboard && window.isSecureContext) {{
    navigator.clipboard.writeText(text).then(ok).catch(function(){{ fallbackCopy(text, ok); }});
  }} else {{ fallbackCopy(text, ok); }}
}}
function fallbackCopy(text, cb){{
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try {{ document.execCommand('copy'); cb(); }} catch (e) {{}}
  document.body.removeChild(ta);
}}
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "iclaw-registry/1.0"

    def _json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _html(self, text, code=200):
        data = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path.rstrip("/") == "/health":
            return self._json({"status": "ok"})
        if u.path.rstrip("/") in ("", "/device-registry"):
            devices = load_devices()
            if q.get("all") == ["1"]:
                return self._json(devices)
            serial = (q.get("serial") or [None])[0]
            if serial and q.get("json") == ["1"]:
                return self._json(devices.get(serial) or {})
            return self._html(render_page(serial, devices))
        self.send_error(404)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path.rstrip("/") != "/api/register":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception as e:
            return self._json({"ok": False, "error": f"bad payload: {e}"}, 400)
        serial = payload.get("serial")
        if not serial or serial == "unknown":
            return self._json({"ok": False, "error": "serial required"}, 400)
        devices = load_devices()
        rec = dict(payload)
        rec["lastSeen"] = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
        devices[str(serial)] = rec
        save_devices(devices)
        return self._json({"ok": True, "serial": str(serial), "devices": len(devices)})

    def log_message(self, fmt, *args):
        import sys
        sys.stderr.write("[registry] " + (fmt % args) + "\n")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "1420"))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
