#!/usr/bin/env python3
"""Read state and change only Waydroid configuration/overlays; never game data.

All destructive paths are fixed here. Backups are root-owned, complete snapshots
of the overlay/configuration, not of Android userdata or base image contents.
"""
import configparser
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

WD = Path('/var/lib/waydroid')
STATE = Path('/var/lib/mwi')
IMAGE = Path('/etc/waydroid-extra/images')
SNAPSHOT = ('waydroid.cfg', 'waydroid_base.prop', 'waydroid.prop', 'overlay', 'mwi-houdini.json')
LIBNB = {
    'system/lib/libnb.so': '13f8b1ed1f778faebc795affff2f540c8422d77f98e0a9a5f8e069d858a4cb2d',
    'system/lib64/libnb.so': '3603eb91a9149bc990df1862f508fefc7855beb92d59f33a40a255a45d468548',
}
HOUDINI_REV = '81f2a51ef539a35aead396ab7fce2adf89f46e88'
HOUDINI_MD5 = 'fbff756612b4144797fbc99eadcb6653'
PROPS = {
    'bridge': {
        'ro.product.cpu.abilist': 'x86_64,x86,arm64-v8a,armeabi-v7a,armeabi',
        'ro.product.cpu.abilist32': 'x86,armeabi-v7a,armeabi',
        'ro.product.cpu.abilist64': 'x86_64,arm64-v8a',
        'ro.dalvik.vm.native.bridge': 'libnb.so',
        'ro.enable.native.bridge.exec': '1',
        'ro.dalvik.vm.isa.arm': 'x86',
        'ro.dalvik.vm.isa.arm64': 'x86_64',
    },
}


def digest(path, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def no_symlink_parents(path, include_leaf=False):
    path = Path(path).absolute()
    parts = [*path.parents]
    if include_leaf:
        parts.append(path)
    for part in parts:
        if part.is_symlink():
            raise ValueError(f'シンボリックリンク経由の変更を拒否: {part}')


def atomic_bytes(path, data, mode=0o644):
    path = Path(path)
    no_symlink_parents(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.mwi-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def read_config():
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    if not cfg.read(WD / 'waydroid.cfg') or 'waydroid' not in cfg:
        raise ValueError('Waydroid設定を読み取れません。初期化途中か破損の可能性があります。')
    return cfg


def save_config(cfg):
    import io
    out = io.StringIO()
    cfg.write(out)
    atomic_bytes(WD / 'waydroid.cfg', out.getvalue().encode())


def inspect():
    if not (WD / 'waydroid.cfg').is_file():
        print('状態: 未初期化または初期化途中' if WD.exists() else '状態: Waydroid環境なし')
        return
    try:
        cfg = read_config()
    except Exception as e:
        print(f'状態: 設定が不正 ({e})')
        return
    print('状態: 初期化済み')
    for key in ('arch', 'images_path', 'system_type', 'mount_overlays', 'suspend_action'):
        print(f'{key}: {cfg["waydroid"].get(key, "未記録")}')
    for key in ('ro.dalvik.vm.native.bridge', 'ro.hardware.egl', 'ro.hardware.gralloc'):
        print(f'{key}: {cfg.get("properties", key, fallback="未指定")}')


def android_release_offline():
    cfg = read_config()
    images = Path(cfg['waydroid'].get('images_path', str(WD / 'images')))
    image = images / 'system.img'
    if not image.is_file():
        raise ValueError(f'初期化済みsystem.imgがありません: {image}')
    if not shutil.which('debugfs'):
        raise ValueError('停止中のAndroid版確認にはdebugfs（e2fsprogs）が必要です。')
    for name in ('/system/build.prop', '/build.prop'):
        result = subprocess.run(['debugfs', '-R', f'cat {name}', str(image)],
                                capture_output=True, text=True, timeout=30)
        match = re.search(r'^ro\.build\.version\.release=(.*)$', result.stdout, re.M)
        if match:
            print(match[1].strip())
            return
    raise ValueError('system.imgからAndroid版を確認できません。新規初期化は自動実行しません。')


def check_libnb(root):
    for relative, expected in LIBNB.items():
        src = Path(root) / 'test_nb' / relative.removeprefix('system/')
        if digest(src) != expected:
            raise ValueError(f'同梱libnb破損: {relative}')
    print('同梱libnb: SHA-256一致')


def check_installed():
    failed = False
    for relative, expected in LIBNB.items():
        path = WD / 'overlay' / relative
        actual = digest(path) if path.is_file() else None
        label = '一致' if actual == expected else ('なし' if actual is None else '異なる')
        print(f'{label}: {relative}')
        failed |= actual != expected
    manifest = WD / 'mwi-houdini.json'
    if manifest.is_file():
        data = json.loads(manifest.read_text())
        for relative, expected in data['files'].items():
            path = WD / 'overlay' / relative
            match = path.is_file() and digest(path) == expected
            print(f'{"一致" if match else "異なる/なし"}: {relative}')
            failed |= not match
    else:
        print('Houdini: MWIの検証記録なし。既存ライブラリの版は未確定。')
    if failed:
        raise ValueError('同梱構成との違いを検出')


def copy_path(src, dst):
    if src.is_symlink():
        dst.symlink_to(os.readlink(src))
    elif src.is_dir():
        shutil.copytree(src, dst, symlinks=True, copy_function=shutil.copy2)
    else:
        shutil.copy2(src, dst)


def inventory(path):
    result = {}
    def visit(p, name):
        if p.is_symlink():
            result[name] = {'type': 'link', 'target': os.readlink(p)}
        elif p.is_dir():
            result[name] = {'type': 'directory'}
            for child in sorted(p.iterdir()):
                visit(child, name + '/' + child.name)
        elif p.is_file():
            result[name] = {'type': 'file', 'sha256': digest(p)}
        else:
            raise ValueError(f'バックアップ対象に特殊ファイルがあります: {p}')
    visit(Path(path), '.')
    return result


def backup(uid):
    no_symlink_parents(WD, include_leaf=True)
    no_symlink_parents(STATE, include_leaf=True)
    root = STATE / 'backups'
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    dest = Path(tempfile.mkdtemp(prefix=time.strftime('%Y%m%d-%H%M%S-'), dir=root))
    data = {'format': 1, 'uid': uid, 'part': 'bridge', 'root': str(WD), 'files': {}, 'inventory': {}}
    for relative in SNAPSHOT:
        src = WD / relative
        no_symlink_parents(src)
        present = src.exists() or src.is_symlink()
        data['files'][relative] = present
        if present:
            copy_path(src, dest / relative)
            data['inventory'][relative] = inventory(dest / relative)
    # The manifest is written last: an interrupted copy cannot be restored.
    atomic_bytes(dest / 'manifest.json', json.dumps(data, indent=2).encode(), 0o600)
    print(dest)


def validate_owner(path, manifest):
    if path.stat().st_uid != 0 or path.stat().st_mode & 0o022:
        raise ValueError('バックアップ所有者/権限が不正です。')
    if manifest.is_symlink() or manifest.stat().st_uid != 0:
        raise ValueError('バックアップmanifestが不正です。')


def validate_backup(path, uid):
    path = Path(path).absolute()
    root = STATE / 'backups'
    if path.parent != root or not path.name:
        raise ValueError('MWIのバックアップフォルダを指定してください。')
    no_symlink_parents(path, include_leaf=True)
    manifest = path / 'manifest.json'
    validate_owner(path, manifest)
    data = json.loads(manifest.read_text())
    if data.get('format') != 1 or data.get('uid') != uid or data.get('root') != str(WD):
        raise ValueError('対象ユーザー/Waydroidが一致しません。')
    if set(data.get('files', {})) != set(SNAPSHOT):
        raise ValueError('復元対象一覧が不正です。')
    for relative, present in data['files'].items():
        if type(present) is not bool:
            raise ValueError('manifestの状態が不正です。')
        src = path / relative
        if present and not (src.exists() or src.is_symlink()):
            raise ValueError(f'バックアップ不足: {relative}')
        if present and inventory(src) != data.get('inventory', {}).get(relative):
            raise ValueError(f'バックアップ内容が破損/変更されています: {relative}')
    return path, data


def remove_path(path):
    no_symlink_parents(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def restore(path, uid):
    path, data = validate_backup(path, uid)
    no_symlink_parents(WD, include_leaf=True)
    for relative in SNAPSHOT:
        target = WD / relative
        remove_path(target)
        if data['files'][relative]:
            copy_path(path / relative, target)
    print('設定とoverlayを復元しました。Android userdataは変更していません。')


def enable_overlays():
    cfg = read_config()
    cfg['waydroid']['mount_overlays'] = 'True'
    save_config(cfg)


def set_network_policy():
    cfg = read_config()
    previous = cfg['waydroid'].get('suspend_action', 'freeze')
    cfg['waydroid']['suspend_action'] = 'stop'
    save_config(cfg)
    print(f'背景化時の動作: {previous} -> stop（freeze/thawを避けてroute喪失を抑制）')


def check_network_policy():
    cfg = read_config()
    action = cfg['waydroid'].get('suspend_action', 'freeze')
    print(f'suspend_action: {action}')
    if action != 'stop':
        raise ValueError('suspend_action=stopが反映されていません。')


def set_props():
    cfg = read_config()
    if not cfg.has_section('properties'):
        cfg.add_section('properties')
    for key, value in PROPS['bridge'].items():
        cfg['properties'][key] = value
    save_config(cfg)
    base = WD / 'waydroid_base.prop'
    lines = base.read_text().splitlines() if base.exists() else []
    lines = [line for line in lines if line.split('=', 1)[0].strip() not in PROPS['bridge']]
    lines += [f'{key}={value}' for key, value in PROPS['bridge'].items()]
    atomic_bytes(base, ('\n'.join(lines) + '\n').encode())


def extract_image(archive, target):
    target = Path(target)
    if target not in (IMAGE / 'system.img', IMAGE / 'vendor.img'):
        raise ValueError('イメージ配置先が不正です。')
    no_symlink_parents(target)
    with zipfile.ZipFile(archive) as z:
        infos = [i for i in z.infolist() if i.filename == target.name]
        if len(infos) != 1 or infos[0].file_size <= 0:
            raise ValueError('イメージがZIPルートに一つ必要です。')
        fd, tmp = tempfile.mkstemp(prefix='.mwi-image-', dir=target.parent)
        try:
            with z.open(infos[0]) as source, os.fdopen(fd, 'wb') as out:
                shutil.copyfileobj(source, out, 1024 * 1024)
            os.chmod(tmp, 0o644)
            os.replace(tmp, target)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)


def verify_houdini(archive):
    # Same pinned archive MD5 as upstream; verify installed binaries by SHA-256.
    if digest(archive, 'md5') != HOUDINI_MD5:
        raise ValueError('Houdini取得物が指定revisionのMD5と一致しません。')
    prefix = f'vendor_intel_proprietary_houdini-{HOUDINI_REV}/prebuilts/'
    values = {}
    with zipfile.ZipFile(archive) as z:
        for relative in ('lib/libhoudini.so', 'lib64/libhoudini.so', 'bin/houdini', 'bin/houdini64'):
            value = hashlib.sha256(z.read(prefix + relative)).hexdigest()
            target = WD / 'overlay/system' / relative
            if not target.is_file() or digest(target) != value:
                raise ValueError(f'Houdini配置不一致: {relative}')
            values['system/' + relative] = value
    atomic_bytes(WD / 'mwi-houdini.json', json.dumps({'revision': HOUDINI_REV, 'files': values}, indent=2).encode())
    print('Houdini 11取得物と配置先の32/64-bitバイナリ一致')


def verify_runtime():
    values = dict(LIBNB)
    manifest = WD / 'mwi-houdini.json'
    if not manifest.is_file():
        raise ValueError('Houdini検証記録がありません。')
    values.update(json.loads(manifest.read_text())['files'])
    for name, expected in values.items():
        result = subprocess.run(['waydroid', 'shell', '--', 'sha256sum', '/' + name],
                                capture_output=True, text=True, timeout=15, check=True)
        if not result.stdout.split() or result.stdout.split()[0] != expected:
            raise ValueError(f'Android内で配置不一致: /{name}')
    print('Android内の対象ファイル: SHA-256一致（アプリでの読み込み成功は別途確認）')


def reset(user_data, uid, report):
    import pwd
    home = Path(pwd.getpwuid(uid).pw_dir).absolute()
    user_data = Path(user_data).absolute()
    if home not in user_data.parents or user_data.name != 'waydroid':
        raise ValueError('現在ユーザーのホーム内にあるWaydroidデータだけ退避できます。')
    targets = (WD, user_data, IMAGE)
    mounts = subprocess.run(['findmnt', '-rn', '-o', 'TARGET'], capture_output=True, text=True, check=True).stdout.splitlines()
    changes = []
    stamp = time.strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid())
    for target in targets:
        no_symlink_parents(target, include_leaf=True)
        if any(m == str(target) or m.startswith(str(target) + '/') for m in mounts):
            raise ValueError(f'マウントが残っています。退避中止: {target}')
        dest = target.with_name(target.name + '.mwi-backup-' + stamp)
        if dest.exists():
            raise ValueError(f'退避先が既にあります: {dest}')
        if target.exists():
            changes.append({'from': str(target), 'to': str(dest), 'moved': False})
    # Record the recovery plan before changing any directory.
    atomic_bytes(report, json.dumps(changes, indent=2).encode(), 0o600)
    for item in changes:
        os.rename(item['from'], item['to'])
        item['moved'] = True
        atomic_bytes(report, json.dumps(changes, indent=2).encode(), 0o600)
        print(f'退避: {item["from"]} -> {item["to"]}')


def main():
    op, *args = sys.argv[1:]
    if op == 'inspect': inspect()
    elif op == 'android-release-offline': android_release_offline()
    elif op == 'check-libnb': check_libnb(args[0])
    elif op == 'check-installed': check_installed()
    elif op == 'backup': backup(int(args[0]))
    elif op == 'inspect-backup':
        path, data = validate_backup(args[0], int(args[1]))
        print(path, json.dumps(data, ensure_ascii=False, indent=2))
    elif op == 'restore': restore(args[0], int(args[1]))
    elif op == 'enable-overlays': enable_overlays()
    elif op == 'set-network-policy': set_network_policy()
    elif op == 'check-network-policy': check_network_policy()
    elif op == 'set-props': set_props()
    elif op == 'extract-image': extract_image(args[0], args[1])
    elif op == 'verify-houdini': verify_houdini(args[0])
    elif op == 'verify-runtime': verify_runtime()
    elif op == 'reset': reset(args[0], int(args[1]), args[2])
    else: raise ValueError(f'不明な操作: {op}')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'[エラー] {e}', file=sys.stderr)
        sys.exit(1)
