#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# MWI v0.1.2: bootstrap for x86_64 AMD Radeon Linux desktops.
# Houdini is obtained by casualsnek/waydroid_script at setup time. It is not
# bundled or redistributed by this repository.

readonly SYSTEM_ZIP='lineage-18.1-20250628-GAPPS-waydroid_x86_64-system.zip'
readonly VENDOR_ZIP='lineage-18.1-20250628-MAINLINE-waydroid_x86_64-vendor.zip'
readonly SYSTEM_URL="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/${SYSTEM_ZIP}/download"
readonly VENDOR_URL="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/${VENDOR_ZIP}/download"
readonly WAYDROID_SCRIPT_REPO='https://github.com/casualsnek/waydroid_script.git'
readonly WAYDROID_SCRIPT_COMMIT='48dbfaf34a6ddbe78688c530f9ba1c26522aafb2'
readonly LIBNB32_SHA='5274b82eb756f8ca0a384c0ed2c555557395e4d21a32a925727ecbb489ffb51d'
readonly LIBNB64_SHA='c221eb6770453df298a32bedbcf82a6147f639a1294f37d758f3bcb102852e34'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIBNB32="$SCRIPT_DIR/payload/lib/libnb.so"
readonly LIBNB64="$SCRIPT_DIR/payload/lib64/libnb.so"
readonly WORK_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/mwi"
readonly CACHE_DIR="$WORK_ROOT/cache"
readonly WAYDROID_SCRIPT_DIR="$WORK_ROOT/waydroid_script"
readonly IMAGE_DIR='/etc/waydroid-extra/images'
readonly RESET_WAYDROID="${RESET_WAYDROID:-0}"
HOST_FAMILY=''
HOST_CODENAME=''
PYTHON_BIN=''

msg() { printf '\n==> %s\n' "$*"; }
ok() { printf '[成功] %s\n' "$*"; }
warn() { printf '[注意] %s\n' "$*" >&2; }
die() { printf '[エラー] %s\n' "$*" >&2; exit 1; }
trap 'ec=$?; printf "[エラー] 終了コード=%s 行=%s\n" "$ec" "${BASH_LINENO[0]:-?}" >&2; exit "$ec"' ERR

download() {
    local url="$1" out="$2"
    [[ -s "$out" ]] && { ok "cached: $(basename "$out")"; return; }
    curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 "$url" -o "$out.part"
    mv "$out.part" "$out"
}

detect_host() {
    case "${ID:-}" in
        cachyos|arch) HOST_FAMILY='arch' ;;
        fedora)
            [[ ! -e /run/ostree-booted ]] || die 'Fedora Atomic/Silverblue/Kinoiteは対象外です。'
            HOST_FAMILY='fedora'
            ;;
        ubuntu)
            [[ "${VERSION_ID:-}" == 24.04 && "${VERSION_CODENAME:-}" == noble ]] || die 'Ubuntuの実験対応は24.04 LTS（noble）のみです。'
            HOST_FAMILY='ubuntu'
            HOST_CODENAME='noble'
            ;;
        *)
            case " ${ID_LIKE:-} " in
                *' arch '*) HOST_FAMILY='arch' ;;
                *) die '対応OSはCachyOS/Arch、通常のdnf版Fedora、Ubuntu 24.04 LTSです。' ;;
            esac
            ;;
    esac
}

preflight() {
    [[ $EUID -ne 0 ]] || die '通常ユーザーで実行してください。installerをsudoで起動しないでください。'
    [[ "$(uname -m)" == x86_64 ]] || die 'x86_64ホストが必要です。'
    [[ -r /etc/os-release ]] || die '/etc/os-releaseが見つかりません。'
    # shellcheck disable=SC1091
    source /etc/os-release
    detect_host
    if [[ "$HOST_FAMILY" == ubuntu ]]; then
        [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || die 'UbuntuではWaylandセッションにログインして実行してください。'
        warn 'Ubuntu 24.04 LTS対応は実験段階です。実機での導入検証は未実施です。'
    fi
    [[ -d /sys/module/amdgpu ]] || warn 'amdgpuが未ロードです。パッケージ導入後に再確認します。'
    [[ -f "$LIBNB32" && -f "$LIBNB64" ]] || die '同梱payloadが見つかりません。'
    [[ "$(sha256sum "$LIBNB32" | awk '{print $1}')" == "$LIBNB32_SHA" ]] || die '32-bit libnbのSHA-256が一致しません。'
    [[ "$(sha256sum "$LIBNB64" | awk '{print $1}')" == "$LIBNB64_SHA" ]] || die '64-bit libnbのSHA-256が一致しません。'
    if [[ -e /var/lib/waydroid/waydroid.cfg || -d "$HOME/.local/share/waydroid" ]]; then
        if [[ "$RESET_WAYDROID" == 1 ]]; then
            reset_existing_waydroid
        else
            die 'Waydroidの既存設定またはユーザーデータを検出しました。クリーン再構築する場合は RESET_WAYDROID=1 ./install.sh を実行してください。'
        fi
    fi
    sudo -v
    ok "ホストを確認しました: ${PRETTY_NAME:-${ID:-unknown}} ($HOST_FAMILY)"
    [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || warn 'Waylandデスクトップセッションを推奨します。'
}

install_packages() {
    msg "Installing host packages ($HOST_FAMILY)"
    case "$HOST_FAMILY" in
        arch)
            sudo pacman -Syu --needed --noconfirm \
                waydroid mesa vulkan-radeon linux-firmware-amdgpu \
                curl git unzip lzip python pipewire pipewire-pulse wireplumber
            PYTHON_BIN="$(command -v python3 || command -v python)"
            ;;
        fedora)
            sudo dnf install -y \
                waydroid waydroid-selinux \
                mesa-dri-drivers mesa-vulkan-drivers \
                amd-gpu-firmware \
                curl git unzip lzip python3 python3-pip \
                pipewire pipewire-pulseaudio wireplumber
            PYTHON_BIN="$(command -v python3)"
            ;;
        ubuntu)
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl software-properties-common
            sudo add-apt-repository -y universe
            # Use the same signed repository as the official Waydroid setup.
            local key_file="$WORK_ROOT/waydroid.gpg"
            curl --proto '=https' --tlsv1.2 -fL --retry 5 \
                https://repo.waydro.id/waydroid.gpg -o "$key_file"
            [[ -s "$key_file" ]] || die 'Waydroidリポジトリの署名鍵を取得できませんでした。'
            sudo install -D -m 0644 "$key_file" /usr/share/keyrings/waydroid.gpg
            printf 'deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ %s main\n' "$HOST_CODENAME" | \
                sudo tee /etc/apt/sources.list.d/waydroid.list >/dev/null
            sudo apt-get update
            sudo apt-get install -y \
                waydroid libgl1-mesa-dri mesa-vulkan-drivers linux-firmware \
                curl git unzip lzip python3 python3-venv python3-pip \
                pipewire pipewire-pulse wireplumber
            PYTHON_BIN="$(command -v python3)"
            ;;
    *) die "未対応のOSです: $HOST_FAMILY" ;;
    esac
    [[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]] || die 'パッケージ導入後にPythonが見つかりません。'
    for command_name in waydroid curl git unzip sha256sum; do
        command -v "$command_name" >/dev/null 2>&1 || die "必要なコマンドが見つかりません: $command_name"
    done
}

check_amd() {
    msg 'Checking AMD graphics'
    sudo modprobe amdgpu >/dev/null 2>&1 || true
    [[ -d /sys/module/amdgpu ]] || die 'amdgpuカーネルモジュールがロードされていません。'
    find /dev/dri -maxdepth 1 -type c -name 'renderD*' -print -quit 2>/dev/null | grep -q . || die 'DRM render nodeが見つかりません。'
    ok 'amdgpuとDRM render nodeを確認しました。'
}

stop_waydroid() {
    waydroid session stop >/dev/null 2>&1 || true
    sudo systemctl stop waydroid-container.service >/dev/null 2>&1 || true
    sleep 1
}

reset_existing_waydroid() {
    msg 'Resetting existing Waydroid environment'
    stop_waydroid
    local backup_dir="$WORK_ROOT/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ -d /var/lib/waydroid/data ]]; then
        warn "既存Android userdataを $backup_dir/waydroid-data.tar.gz に退避します。"
        sudo tar -C /var/lib/waydroid -cf - data | gzip >"$backup_dir/waydroid-data.tar.gz"
    fi
    if [[ -d "$HOME/.local/share/waydroid" ]]; then
        tar -C "$HOME/.local/share" -czf "$backup_dir/user-waydroid.tar.gz" waydroid
    fi

    sudo rm -rf /var/lib/waydroid
    rm -rf "$HOME/.local/share/waydroid"
    sudo rm -rf "$IMAGE_DIR"
    ok '既存Waydroid環境を退避して削除しました。'
}

start_waydroid() {
    sudo systemctl enable --now waydroid-container.service >/dev/null
    (waydroid session start >"$WORK_ROOT/session.log" 2>&1 &) || true
}

wait_android() {
    local attempt
    for attempt in $(seq 1 120); do
        if [[ "$(sudo waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
            sudo waydroid shell pm path android >/dev/null 2>&1 && return 0
        fi
        sleep 1
    done
    die 'Androidの起動がタイムアウトしました。'
}

install_android11() {
    msg 'Downloading pinned Android 11 + GApps images'
    mkdir -p "$CACHE_DIR"
    download "$SYSTEM_URL" "$CACHE_DIR/$SYSTEM_ZIP"
    download "$VENDOR_URL" "$CACHE_DIR/$VENDOR_ZIP"
    unzip -tq "$CACHE_DIR/$SYSTEM_ZIP" >/dev/null || die 'systemイメージのZIP整合性を確認できません。'
    unzip -tq "$CACHE_DIR/$VENDOR_ZIP" >/dev/null || die 'vendorイメージのZIP整合性を確認できません。'
    unzip -Z1 "$CACHE_DIR/$SYSTEM_ZIP" | grep -qx 'system.img' || die 'system ZIPのルートにsystem.imgがありません。'
    unzip -Z1 "$CACHE_DIR/$VENDOR_ZIP" | grep -qx 'vendor.img' || die 'vendor ZIPのルートにvendor.imgがありません。'
    sudo install -d -m 0755 "$IMAGE_DIR"
    sudo unzip -oq "$CACHE_DIR/$SYSTEM_ZIP" -d "$IMAGE_DIR"
    sudo unzip -oq "$CACHE_DIR/$VENDOR_ZIP" -d "$IMAGE_DIR"
    [[ -s "$IMAGE_DIR/system.img" && -s "$IMAGE_DIR/vendor.img" ]] || die 'イメージを展開できませんでした。'
    sudo waydroid init -f
    stop_waydroid
    start_waydroid
    wait_android
    [[ "$(sudo waydroid shell getprop ro.build.version.release | tr -d '\r')" == 11* ]] || die 'Android 11を確認できません。'
    sudo waydroid shell pm path com.android.vending >/dev/null 2>&1 || die '選択したイメージにGoogle Play Storeがありません。'
}

prepare_waydroid_script() {
    msg 'Preparing pinned waydroid_script'
    rm -rf -- "$WAYDROID_SCRIPT_DIR"
    git init "$WAYDROID_SCRIPT_DIR" >/dev/null
    git -C "$WAYDROID_SCRIPT_DIR" remote add origin "$WAYDROID_SCRIPT_REPO"
    git -C "$WAYDROID_SCRIPT_DIR" fetch --depth=1 origin "$WAYDROID_SCRIPT_COMMIT"
    git -C "$WAYDROID_SCRIPT_DIR" checkout --detach FETCH_HEAD
    local actual_commit
    actual_commit="$(git -C "$WAYDROID_SCRIPT_DIR" rev-parse HEAD)"
    [[ "$actual_commit" == "$WAYDROID_SCRIPT_COMMIT" ]] || die "waydroid_script commit verification failed: $actual_commit"
    ok "waydroid_script commitを確認しました: $actual_commit"
    "$PYTHON_BIN" -m venv "$WAYDROID_SCRIPT_DIR/venv"
    "$WAYDROID_SCRIPT_DIR/venv/bin/python" -m pip install --disable-pip-version-check -r "$WAYDROID_SCRIPT_DIR/requirements.txt"
    ok 'waydroid_scriptは固定commitを無改変で使用します。'
}

install_houdini() {
    msg 'Installing Houdini through waydroid_script'
    stop_waydroid
    (cd "$WAYDROID_SCRIPT_DIR" && sudo "$WAYDROID_SCRIPT_DIR/venv/bin/python" main.py -a 11 install libhoudini)
}

patch_props() {
    sudo "$PYTHON_BIN" - /var/lib/waydroid/waydroid.cfg /var/lib/waydroid/waydroid_base.prop <<'PY'
import configparser
import sys
from pathlib import Path

config_path, base_path = map(Path, sys.argv[1:3])
properties = {
    'ro.product.cpu.abilist': 'x86_64,x86,arm64-v8a,armeabi-v7a,armeabi',
    'ro.product.cpu.abilist32': 'x86,armeabi-v7a,armeabi',
    'ro.product.cpu.abilist64': 'x86_64,arm64-v8a',
    'ro.dalvik.vm.native.bridge': 'libnb.so',
    'ro.enable.native.bridge.exec': '1',
    'ro.enable.native.bridge.exec64': '1',
    'ro.dalvik.vm.isa.arm': 'x86',
    'ro.dalvik.vm.isa.arm64': 'x86_64',
}
config = configparser.ConfigParser()
config.optionxform = str
config.read(config_path)
config.setdefault('properties', {})
for key, value in properties.items():
    config['properties'][key] = value
with config_path.open('w') as output:
    config.write(output, space_around_delimiters=True)
lines = base_path.read_text().splitlines()
written = set()
updated = []
for line in lines:
    key = line.split('=', 1)[0].strip() if '=' in line else ''
    if key in properties:
        if key not in written:
            updated.append(f'{key}={properties[key]}')
            written.add(key)
    else:
        updated.append(line)
for key, value in properties.items():
    if key not in written:
        updated.append(f'{key}={value}')
base_path.write_text('\n'.join(updated) + '\n')
PY
}

install_test_libnb() {
    msg 'Installing bundled MWI test_libnb'
    stop_waydroid
    sudo install -d -m 0755 /var/lib/waydroid/overlay/system/lib /var/lib/waydroid/overlay/system/lib64
    sudo install -m 0644 "$LIBNB32" /var/lib/waydroid/overlay/system/lib/libnb.so
    sudo install -m 0644 "$LIBNB64" /var/lib/waydroid/overlay/system/lib64/libnb.so
    if [[ "$HOST_FAMILY" == fedora ]] && command -v restorecon >/dev/null 2>&1; then
        sudo restorecon -RF /var/lib/waydroid/overlay >/dev/null 2>&1 || true
    fi
    patch_props
    start_waydroid
    wait_android
    [[ "$(sudo waydroid shell getprop ro.dalvik.vm.native.bridge | tr -d '\r')" == libnb.so ]] || die 'NativeBridgeの設定を確認できません。'
    sudo waydroid shell getprop ro.product.cpu.abilist | tr -d '\r' | grep -q arm64-v8a || die 'ARM64 ABIが公開されていません。'
}

wait_waydroid_ipv4() {
    local attempt
    for attempt in $(seq 1 30); do
        if sudo waydroid shell ip -4 -o addr show dev eth0 scope global 2>/dev/null | tr -d '\r' | grep -q ' inet '; then
            return 0
        fi
        sleep 1
    done
    return 1
}

repair_waydroid_network() {
    local host_cidr gateway prefix android_mac lease_ip
    host_cidr="$(ip -4 -o addr show dev waydroid0 2>/dev/null | awk 'NR==1 {print $4}')"
    [[ -n "$host_cidr" ]] || return 1
    gateway="${host_cidr%/*}"
    prefix="${host_cidr#*/}"

    if ! wait_waydroid_ipv4; then
        android_mac="$(sudo waydroid shell cat /sys/class/net/eth0/address 2>/dev/null | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
        lease_ip="$(sudo awk -v mac="$android_mac" 'tolower($2)==mac {ip=$3} END {print ip}' /var/lib/misc/dnsmasq.waydroid0.leases 2>/dev/null || true)"
        if [[ -n "$lease_ip" ]]; then
            warn "DHCP lease ($lease_ip) は存在しますがeth0へIPv4が反映されていません。leaseを一時反映します。"
            printf 'ip link set eth0 up\nip addr replace %s/%s dev eth0\n' "$lease_ip" "$prefix" | sudo waydroid shell >/dev/null
        fi
    fi

    wait_waydroid_ipv4 || return 1

    if ! sudo waydroid shell ip -4 route 2>/dev/null | tr -d '\r' | grep -q '^default '; then
        warn "Waydroidのdefault routeがありません。gateway $gateway を補完します。"
        printf 'ip route replace default via %s dev eth0\n' "$gateway" | sudo waydroid shell >/dev/null
    fi
}

verify_network() {
    sudo waydroid shell ip -4 -o addr show dev eth0 scope global 2>/dev/null | tr -d '\r' | grep -q ' inet ' || return 1
    sudo waydroid shell ip -4 route 2>/dev/null | tr -d '\r' | grep -q '^default ' || return 1
    sudo waydroid shell ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || return 1
    sudo waydroid shell ping -c 1 -W 3 google.com >/dev/null 2>&1 || return 1
}

configure_network() {
    msg 'Configuring Waydroid network access'
    printf '%s\n' \
        'net.ipv4.ip_forward=1' \
        'net.ipv6.conf.all.disable_ipv6=0' \
        'net.ipv6.conf.default.disable_ipv6=0' \
        | sudo tee /etc/sysctl.d/99-waydroid-network.conf >/dev/null
    sudo sysctl -p /etc/sysctl.d/99-waydroid-network.conf >/dev/null || true

    if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | head -1 | grep -qi active; then
        sudo ufw allow in on waydroid0 to any port 67 proto udp >/dev/null || true
        sudo ufw allow in on waydroid0 to any port 53 proto udp >/dev/null || true
        sudo ufw allow in on waydroid0 to any port 53 proto tcp >/dev/null || true
        sudo ufw route allow in on waydroid0 >/dev/null || true
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
        sudo firewall-cmd --permanent --zone=trusted --add-interface=waydroid0 >/dev/null || true
        sudo firewall-cmd --reload >/dev/null || true
    fi

    stop_waydroid
    start_waydroid
    wait_android

    if ! repair_waydroid_network || ! verify_network; then
        warn 'Waydroid network初期化を再試行します。'
        stop_waydroid
        start_waydroid
        wait_android
        repair_waydroid_network || true
    fi

    verify_network || die 'Waydroid network verification failed (eth0 / default route / Internet / DNS).'
    ok 'WaydroidのIPv4、default route、Internet、DNSを確認しました。'
}

launch_play_store() {
    msg 'Starting Waydroid and Google Play'
    systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 || true
    (waydroid show-full-ui >"$WORK_ROOT/full-ui.log" 2>&1 &) || true
    sleep 3
    if waydroid app launch com.android.vending >/dev/null 2>&1; then
        ok 'Google Playの起動を要求しました。'
    else
        warn 'Google Playはインストール済みです。Waydroidのアプリ画面から開いてください。'
    fi
}

main() {
    preflight
    mkdir -p "$WORK_ROOT" "$CACHE_DIR"
    install_packages
    check_amd
    install_android11
    prepare_waydroid_script
    install_houdini
    install_test_libnb
    configure_network
    launch_play_store
    printf '\n'
    ok 'セットアップが完了しました。'
}

main "$@"
