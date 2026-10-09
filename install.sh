#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# MWI 0.2.2: diagnose, repair and install for CachyOS/Arch/Fedora AMD desktops.
# Houdini is obtained by casualsnek/waydroid_script at setup time. It is not
# bundled or redistributed by this repository.

readonly SYSTEM_ZIP='lineage-18.1-20250628-GAPPS-waydroid_x86_64-system.zip'
readonly VENDOR_ZIP='lineage-18.1-20250628-MAINLINE-waydroid_x86_64-vendor.zip'
readonly SYSTEM_URL="https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_x86_64/${SYSTEM_ZIP}/download"
readonly VENDOR_URL="https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_x86_64/${VENDOR_ZIP}/download"
readonly WAYDROID_SCRIPT_REPO='https://github.com/casualsnek/waydroid_script.git'
readonly WAYDROID_SCRIPT_COMMIT='48dbfaf34a6ddbe78688c530f9ba1c26522aafb2'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIBNB32="$SCRIPT_DIR/test_nb/lib/libnb.so"
readonly LIBNB64="$SCRIPT_DIR/test_nb/lib64/libnb.so"
readonly WORK_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/mwi"
readonly CACHE_DIR="$WORK_ROOT/cache"
readonly IMAGE_DIR='/etc/waydroid-extra/images'
HOST_FAMILY=''
PYTHON_BIN=''

msg() { printf '\n==> %s\n' "$*"; }
ok() { printf '[成功] %s\n' "$*"; }
warn() { printf '[注意] %s\n' "$*" >&2; }
die() { printf '[エラー] %s\n' "$*" >&2; exit 1; }

check_amd() {
    msg 'Checking AMD graphics'
    sudo modprobe amdgpu >/dev/null 2>&1 || true
    [[ -d /sys/module/amdgpu ]] || die 'amdgpuカーネルモジュールがロードされていません。'
    find /dev/dri -maxdepth 1 -type c -name 'renderD*' -print -quit 2>/dev/null | grep -q . || die 'DRM render nodeが見つかりません。'
    ok 'amdgpuとDRM render nodeを確認しました。'
}

source "$SCRIPT_DIR/lib/lifecycle.sh"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then lifecycle_main "$@"; fi
