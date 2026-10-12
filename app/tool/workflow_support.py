#!/usr/bin/env python3
"""Small, dependency-free helpers for local verification and release scripts."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request


def config(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise ValueError('无法读取配置，请检查 app/env.json 的路径和 JSON 格式。') from error
    url = data.get('SUPABASE_URL', '')
    key = data.get('SUPABASE_ANON_KEY', '')
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != 'https' or not parsed.hostname or 'REPLACE_ME' in url:
        raise ValueError('请在 app/env.json 填写有效的 Supabase HTTPS 地址。')
    if not isinstance(key, str) or not key or 'REPLACE_ME' in key:
        raise ValueError('请在 app/env.json 填写 Supabase 客户端公开密钥。')
    if key.startswith('sb_secret_'):
        raise ValueError('客户端不能使用服务端密钥，请改用 anon/publishable key。')
    if not key.startswith('sb_publishable_'):
        try:
            payload = key.split('.')[1]
            role = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))['role']
        except (IndexError, KeyError, ValueError, TypeError) as error:
            raise ValueError('Supabase 客户端密钥格式不正确。') from error
        if role != 'anon':
            raise ValueError('客户端不能使用 service_role 密钥。')
    return data


def select_device(path, mode, requested=None):
    devices = json.loads(Path(path).read_text())
    phones = [d for d in devices if d.get('isSupported') and
              d.get('targetPlatform', '').startswith('android') and not d.get('emulator')]
    if requested:
        candidates = [d for d in devices if d.get('id') == requested and d.get('isSupported')]
        if not candidates or (mode in ('phone', 'profile', 'smoke') and candidates[0] not in phones):
            raise ValueError('指定设备未连接或不是 Android 真机。')
        if mode == 'web' and candidates[0].get('id') != 'chrome':
            raise ValueError('web 模式应选择 Chrome。')
        if mode == 'auto' and candidates[0] not in phones and candidates[0].get('id') != 'chrome':
            raise ValueError('本项目验证目标为 Android 真机或 Chrome。')
    elif mode in ('phone', 'profile', 'smoke') or (mode == 'auto' and phones):
        candidates = phones
        if len(candidates) > 1:
            names = ', '.join(f"{d['name']} ({d['id']})" for d in candidates)
            raise ValueError(f'连接了多台手机：{names}。请加 --device <设备ID>。')
    else:
        candidates = [d for d in devices if d.get('id') == 'chrome' and d.get('isSupported')]
    if not candidates:
        if mode in ('phone', 'profile', 'smoke'):
            raise ValueError('没有检测到 Android 真机，请连接 USB、开启 USB 调试并在手机上允许授权。')
        raise ValueError('没有检测到可用的 Chrome，请安装 Chrome 或连接 Android 手机。')
    selected = candidates[0]
    print(selected['id'])
    print(f"已选择：{selected['name']}（{selected.get('sdk', '')}）", file=sys.stderr)


def prepare_cache(app):
    app = Path(app)
    stale = []
    for name in ('.dart_tool', 'build'):
        folder = app / name
        if folder.exists() and any(getattr(p.stat(), 'st_flags', 0) & 0x40000000
                                   for p in folder.rglob('*') if p.is_file()):
            stale.append(folder)
    if not stale:
        return
    backup_root = app / '.workflow-cache-backups'
    backup_root.mkdir(exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='cache-', dir=backup_root))
    apk = app / 'build/app/outputs/flutter-apk/app-release.apk'
    retained = None
    if apk.is_file() and not (getattr(apk.stat(), 'st_flags', 0) & 0x40000000):
        retained = backup / 'last-release.apk'
        shutil.copy2(apk, retained)
    for folder in stale:
        shutil.move(str(folder), str(backup / folder.name))
    if retained:
        apk.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(retained, apk)
    print(f'发现云盘占位的构建缓存，已转移并保留备份：{backup}')


def check_version(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
        raise ValueError('版本号格式应为 1.6.3 或 1.6.3-beta.1。')


def set_version(path, version):
    check_version(version)
    path = Path(path)
    text = path.read_text()
    match = re.search(r'^version:\s*([^\s]+)\s*$', text, re.M)
    if not match:
        raise ValueError('pubspec.yaml 缺少 version 字段。')
    old = match.group(1).partition('+')[2]
    number = max(int(time.time()), int(old or '0') + 1)
    if number > 2147483647:
        raise ValueError('Android 构建号超出允许范围。')
    path.write_text(text[:match.start()] + f'version: {version}+{number}' + text[match.end():])
    print(f'版本设置为 {version}+{number}')


def api_response(payload):
    data = json.loads(payload)
    if data.get('code') != 0:
        raise ValueError(f"蒲公英 API 未成功：code={data.get('code')}，{data.get('message', '请检查配置或网络')}")
    return data.get('data') or {}


def check_pgyer(path):
    data = config(path)
    key = os.environ.get('PGYER_API_KEY', '')
    if not key:
        raise ValueError('未配置上传 API Key，请填写项目根目录的 pgyer_config.sh。')
    app_key = data.get('PGYER_APP_KEY')
    if not app_key:
        raise ValueError('检查现有应用需要在 app/env.json 填写 PGYER_APP_KEY。')
    request = urllib.request.Request('https://www.pgyer.com/apiv2/app/view',
        data=urllib.parse.urlencode({'_api_key': key, 'appKey': app_key}).encode())
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            app = api_response(response.read())
    except urllib.error.HTTPError as error:
        raise ValueError(f'蒲公英检查失败，HTTP {error.code}。') from error
    except urllib.error.URLError as error:
        raise ValueError('无法连接蒲公英，请检查网络后重试。') from error
    identifier = app.get('buildIdentifier', '')
    if identifier and identifier != 'com.lovestory.love_story':
        raise ValueError('PGYER_APP_KEY 指向其他应用，请核对配置。')
    print(f"蒲公英配置验证通过：{app.get('buildName', '爱情心意值')}，当前版本 {app.get('buildVersion', '未知')}")


def curl_quote(value):
    # Feed curl configuration over stdin; private credentials never enter argv.
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'


def upload(apk, note):
    if not Path(apk).is_file():
        raise ValueError('APK 不存在，不能上传。')
    key = os.environ.get('PGYER_API_KEY', '')
    if not key:
        raise ValueError('未配置上传 API Key。')
    with tempfile.TemporaryDirectory(prefix='love-story-upload-') as folder:
        response = Path(folder) / 'response.json'
        lines = [
            'url = "https://upload.pgyer.com/apiv2/app/upload"',
            'connect-timeout = 15', 'max-time = 900', 'silent', 'show-error',
            'fail-with-body', 'output = ' + curl_quote(response),
            'form = ' + curl_quote('file=@' + apk),
            'form-string = ' + curl_quote('_api_key=' + key),
            'form-string = ' + curl_quote('buildUpdateDescription=' + note),
        ]
        result = subprocess.run(['curl', '--config', '-'], input='\n'.join(lines) + '\n',
                                text=True, capture_output=True)
        if result.returncode:
            raise ValueError('上传未成功，请检查网络/API Key。不会自动重复上传；如中断，请先到蒲公英确认发布状态。')
        app = api_response(response.read_text())
        shortcut = app.get('buildShortcutUrl', '')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', shortcut):
            raise ValueError('上传响应缺少有效下载链接，请到蒲公英确认发布状态。')
        print('发布成功：https://www.pgyer.com/' + shortcut)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['config', 'web-config', 'device', 'cache',
        'version-check', 'set-version', 'pgyer-check', 'upload'])
    parser.add_argument('args', nargs='*')
    args = parser.parse_args()
    a = args.args
    if args.action == 'config':
        config(a[0]); print('客户端配置验证通过。')
    elif args.action == 'web-config':
        data = config(a[0])
        Path(a[1]).write_text(json.dumps({k: data[k] for k in ('SUPABASE_URL', 'SUPABASE_ANON_KEY')}))
        os.chmod(a[1], 0o600)
    elif args.action == 'device':
        select_device(a[0], a[1], a[2] if len(a) > 2 else None)
    elif args.action == 'cache':
        prepare_cache(a[0])
    elif args.action == 'version-check':
        check_version(a[0])
    elif args.action == 'set-version':
        set_version(a[0], a[1])
    elif args.action == 'pgyer-check':
        check_pgyer(a[0])
    elif args.action == 'upload':
        upload(a[0], a[1])


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(f'错误：{error}', file=sys.stderr)
        sys.exit(1)
