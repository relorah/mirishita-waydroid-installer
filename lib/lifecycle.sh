#!/usr/bin/env bash
# Overrides the legacy bootstrap entrypoint and unsafe lifecycle functions.
MODE=auto
STAGE=preflight
BACKUP=''
LOG_DIR=''
USER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/waydroid"
PINNED_UPSTREAM="$WORK_ROOT/waydroid_script-$WAYDROID_SCRIPT_COMMIT"

confirm() {
    local answer
    [[ -t 0 ]] || die '変更の確認には対話端末が必要です。--diagnose は非対話でも利用できます。'
    printf '%s [yes/No]: ' "$1"
    IFS= read -r answer || return 1
    [[ "$answer" == yes ]]
}
collect_logs() {
    [[ -n "$LOG_DIR" ]] || return 0
    timeout 10 sudo -n systemctl status waydroid-container.service --no-pager >"$LOG_DIR/service.txt" 2>&1 || true
    timeout 10 sudo -n journalctl -u waydroid-container.service -b -n 200 --no-pager >"$LOG_DIR/journal.txt" 2>&1 || true
    timeout 10 sudo -n cat /var/lib/waydroid/waydroid.log >"$LOG_DIR/waydroid.txt" 2>&1 || true
    timeout 10 sudo -n waydroid shell -- logcat -d -t 500 >"$LOG_DIR/logcat.txt" 2>&1 || true
    timeout 10 sudo -n waydroid shell -- sh -c 'for pid in $(pidof com.bandainamcoent.imas_millionlive_theaterdays); do echo "PID=$pid"; grep -E "libnb|houdini|ndk_translation|libgallium|libGLES|libEGL" /proc/$pid/maps; done' >"$LOG_DIR/game-libraries.txt" 2>&1 || true
    timeout 10 ip -details addr show waydroid0 >"$LOG_DIR/host-waydroid0.txt" 2>&1 || true
    timeout 10 ip route get 1.1.1.1 >"$LOG_DIR/host-egress-route.txt" 2>&1 || true
    timeout 10 sudo -n sysctl net.ipv4.ip_forward >"$LOG_DIR/host-ip-forward.txt" 2>&1 || true
    timeout 10 sudo -n nft list ruleset >"$LOG_DIR/host-nftables.txt" 2>&1 || true
    timeout 10 sudo -n iptables-save >"$LOG_DIR/host-iptables.txt" 2>&1 || true
    timeout 10 sudo -n waydroid shell -- sh -c 'ip -4 addr show dev eth0; ip -4 route; getprop net.dns1; getprop net.dns2; dumpsys connectivity' >"$LOG_DIR/android-network.txt" 2>&1 || true
}
on_exit() {
    local rc=$?
    trap - EXIT
    if (( rc != 0 )); then
        collect_logs
        printf '\n[失敗] 段階=%s 終了コード=%s\nログ: %s\n' "$STAGE" "$rc" "$LOG_DIR" >&2
        [[ -z "$BACKUP" ]] || printf 'バックアップ: %s\n' "$BACKUP" >&2
    fi
    exit "$rc"
}
phase() { STAGE="$1"; msg "$STAGE"; shift; "$@"; }
prop() { timeout 8 sudo waydroid shell -- getprop "$1" 2>/dev/null | tr -d '\r' || true; }
state_tool() { sudo "$PYTHON_BIN" "$SCRIPT_DIR/lib/state.py" "$@"; }
preflight() {
    [[ $EUID -ne 0 ]] || die 'sudoを付けず通常ユーザーで実行してください。'
    [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'Linux x86_64が必要です。'
    for c in sudo timeout sha256sum flock; do command -v "$c" >/dev/null || die "$c が必要です。"; done
    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    [[ -n "$PYTHON_BIN" ]] || die 'python3が必要です。'
    source /etc/os-release
    case "${ID:-}" in arch|cachyos) HOST_FAMILY=arch ;; fedora) HOST_FAMILY=fedora ;; *) HOST_FAMILY=unsupported ;; esac
    if [[ "$HOST_FAMILY" == fedora && -e /run/ostree-booted ]]; then HOST_FAMILY=unsupported; fi
    mkdir -p "$WORK_ROOT/logs" "$CACHE_DIR"
    LOG_DIR="$(mktemp -d "$WORK_ROOT/logs/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
    exec > >(tee -a "$LOG_DIR/install.log") 2>&1
    trap on_exit EXIT
    trap 'printf "[コマンド失敗] 行=%s コマンド=%s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR
    sudo -v
    # Persistent system lock excludes concurrent changes by other users as well.
    sudo install -d -m 0755 /var/lib/mwi
    sudo touch /var/lib/mwi/install.lock
    sudo chmod 0644 /var/lib/mwi/install.lock
    exec 9</var/lib/mwi/install.lock
    flock -n 9 || die '別のMWIが実行中です。'
    state_tool check-libnb "$SCRIPT_DIR"
}
diagnose() {
    msg '状態診断（サービスは起動しません）'
    state_tool inspect
    [[ ! -e "$USER_DATA" ]] || printf 'ユーザーデータ: あり (%s)\n' "$USER_DATA"
    if command -v waydroid >/dev/null; then
        timeout 8 waydroid status || true
        if sudo systemctl is-active --quiet waydroid-container.service; then
            printf 'Android=%s NativeBridge=%s\n' "$(prop ro.build.version.release)" "$(prop ro.dalvik.vm.native.bridge)"
            timeout 10 sudo waydroid shell -- dumpsys SurfaceFlinger >"$LOG_DIR/surfaceflinger.txt" 2>&1 || true
            grep -iE 'GLES:|GL_RENDERER|GL_VERSION' "$LOG_DIR/surfaceflinger.txt" || true
        fi
    fi
    state_tool check-installed || warn '同梱構成との違いがあります。上の一覧を確認してください。'
    printf 'ログ: %s\n' "$LOG_DIR"
}
install_packages() {
    local -a packages=()
    case "$HOST_FAMILY" in
        arch) packages=(waydroid mesa vulkan-radeon linux-firmware-amdgpu curl git unzip lzip python python-pip e2fsprogs iptables iproute2 util-linux) ;;
        fedora) packages=(waydroid waydroid-selinux mesa-dri-drivers mesa-vulkan-drivers amd-gpu-firmware curl-minimal git unzip lzip python3 python3-pip e2fsprogs iptables-nft iproute util-linux policycoreutils) ;;
        *) die 'CachyOS/Archまたはdnf版Fedoraが必要です。' ;;
    esac
    local -a missing=()
    local p
    for p in "${packages[@]}"; do
        if [[ "$HOST_FAMILY" == arch ]]; then
            pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
        else
            if [[ "$p" == curl-minimal ]] && command -v curl >/dev/null; then continue; fi
            rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
        fi
    done
    if (( ${#missing[@]} )); then
        printf '不足: %s\n' "${missing[*]}"
        confirm 'システム全体を更新して不足パッケージを導入しますか' || die 'パッケージ導入を中止しました。'
        if [[ "$HOST_FAMILY" == arch ]]; then
            sudo pacman -Syu --needed "${missing[@]}"
        else
            sudo dnf upgrade --refresh
            sudo dnf install "${missing[@]}"
        fi
    fi
    [[ -d "/usr/lib/modules/$(uname -r)" ]] || die '実行中カーネルのモジュールがありません。再起動後に再実行してください。'
    sudo modprobe binder_linux >/dev/null 2>&1 || true
    grep -qw binder /proc/filesystems || die 'binderfsを確認できません。Waydroid対応カーネルを確認してください。'
    check_amd
}
restore_selinux_contexts() {
    [[ "$HOST_FAMILY" == fedora ]] || return 0
    local path
    for path in /var/lib/waydroid /etc/waydroid-extra/images; do
        if sudo test -d "$path"; then sudo restorecon -RF "$path"; fi
    done
}
prepare_firewalld() {
    command -v firewall-cmd >/dev/null || return 0
    sudo firewall-cmd --state >/dev/null 2>&1 || return 0
    local zone
    zone="$(sudo firewall-cmd --get-zone-of-interface=waydroid0 2>/dev/null || true)"
    [[ "$zone" != trusted ]] || return 0
    if [[ -n "$zone" && "$zone" != 'no zone' ]]; then
        warn "waydroid0は既存zone $zone に属しています。自動変更せず、疎通を確認します。"
        return 0
    fi
    confirm 'firewalldでwaydroid0を実行中のみtrusted zoneへ追加しますか（Androidからホストへの通信も許可。firewalld再起動で解除）' || die 'firewalldの例外追加を中止しました。'
    sudo firewall-cmd --zone=trusted --add-interface=waydroid0
}
stop_waydroid() {
    waydroid session stop || true
    sudo systemctl stop waydroid-container.service
    local n mounts
    for n in $(seq 1 20); do
        mounts="$(sudo findmnt -rn -o TARGET)" || die 'マウント状態を取得できません。変更を中止します。'
        if ! sudo systemctl is-active --quiet waydroid-container.service &&
            ! grep -qE '^/var/lib/waydroid/(rootfs|overlay_rw|overlay_work)(/|$)' <<< "$mounts"; then return 0; fi
        sleep 1
    done
    die '停止・マウント解除を確認できません。ファイル変更を中止しました。'
}
start_waydroid() {
    prepare_firewalld
    sudo systemctl enable --now waydroid-container.service
    (waydroid session start >>"$LOG_DIR/session.txt" 2>&1 9>&- &)
}
wait_android() {
    local deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        [[ "$(prop sys.boot_completed)" != 1 ]] || return 0
        sudo systemctl is-active --quiet waydroid-container.service || die 'Waydroidサービスが起動後に停止しました。'
        sleep 1
    done
    die 'Androidが起動しません。サービスとAndroidのログを保存します。'
}
android_route() {
    timeout 8 sudo waydroid shell -- ip -4 route 2>/dev/null | tr -d '\r' || true
}
android_ipv4() {
    timeout 8 sudo waydroid shell -- ip -4 -o addr show dev eth0 2>/dev/null | tr -d '\r' || true
}
android_has_ipv4() {
    grep -qE 'inet 192\.168\.240\.([2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])/24([[:space:]]|$)' <<<"$1"
}
wait_network_ipv4() {
    local deadline=$((SECONDS + 20)) addr
    while (( SECONDS < deadline )); do
        addr="$(android_ipv4)"
        if android_has_ipv4 "$addr"; then return 0; fi
        sleep 1
    done
    return 1
}
network_snapshot() {
    ip -details addr show waydroid0 >"$LOG_DIR/network-host-interface.txt" 2>&1 || true
    ip route get 1.1.1.1 >"$LOG_DIR/network-host-egress.txt" 2>&1 || true
    sudo sysctl net.ipv4.ip_forward >"$LOG_DIR/network-ip-forward.txt" 2>&1 || true
    sudo nft list ruleset >"$LOG_DIR/network-nftables.txt" 2>&1 || true
    local ipt
    ipt="$(command -v iptables-legacy || command -v iptables || true)"
    if [[ -n "$ipt" ]]; then
        {
            printf 'backend: %s\n' "$ipt"
            sudo "$ipt" -C INPUT -i waydroid0 -p udp --dport 53 -j ACCEPT 2>&1 || true
            sudo "$ipt" -C INPUT -i waydroid0 -p udp --dport 67 -j ACCEPT 2>&1 || true
            sudo "$ipt" -C FORWARD -i waydroid0 -j ACCEPT 2>&1 || true
            sudo "$ipt" -C FORWARD -o waydroid0 -j ACCEPT 2>&1 || true
            sudo "$ipt" -t nat -C POSTROUTING -s 192.168.240.0/24 '!' -d 192.168.240.0/24 -j MASQUERADE 2>&1 || true
        } >"$LOG_DIR/network-iptables-rules.txt"
    fi
    if command -v ufw >/dev/null; then sudo ufw status verbose >"$LOG_DIR/network-ufw.txt" 2>&1 || true; fi
    if command -v firewall-cmd >/dev/null; then sudo firewall-cmd --get-active-zones >"$LOG_DIR/network-firewalld.txt" 2>&1 || true; fi
    timeout 10 sudo waydroid shell -- sh -c 'ip -4 addr show dev eth0; ip -4 route; printf "net.dns1="; getprop net.dns1; printf "net.dns2="; getprop net.dns2; dumpsys connectivity' >"$LOG_DIR/network-android.txt" 2>&1 || true
}
network_restart() {
    msg 'Waydroidのネットワークを再生成します'
    stop_waydroid
    prepare_firewalld
    sudo systemctl start waydroid-container.service
    (waydroid session start >>"$LOG_DIR/session-network-restart.txt" 2>&1 9>&- &)
    wait_android
    wait_network_ipv4 || die '再起動後もDHCPのIPv4を取得できません。dnsmasqの状態を確認してください。'
}
dns_resolved() {
    # ping resolves through Android's resolver before sending ICMP. A resolved
    # PING header is evidence of DNS even if the destination blocks ICMP.
    grep -qE '^PING play\.googleapis\.com \([0-9a-fA-F:.]+\)' "$1"
}
https_responded() {
    # Match a response status line, never a GET / HTTP/1.1 request.
    grep -qE '^HTTP/[0-9.]+ [1-5][0-9][0-9]([[:space:]]|$)' "$1"
}
android_https_test() {
    timeout 15 sudo waydroid shell -- sh -c 'if command -v curl >/dev/null 2>&1; then curl --noproxy "*" -I --connect-timeout 5 --max-time 10 https://play.googleapis.com/; else toybox wget -d -O /dev/null https://play.googleapis.com/; fi' >"$1" 2>&1 || true
    https_responded "$1" && return 0
    # A11 images may have no TLS-capable command. Use host curl inside the
    # container's network namespace, with an address resolved by Android.
    # This checks container egress/TLS with host CA certificates, not Play login.
    local pid address dns_file="${1/https-test/dns-test}" fallback="${1%.txt}-namespace.txt"
    address="$(sed -nE 's/^PING play\.googleapis\.com \(([0-9.]+)\).*/\1/p' "$dns_file" | head -n 1)"
    [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    pid="$(timeout 5 sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid -pH 2>/dev/null)" || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    timeout 15 sudo nsenter -t "$pid" -n -- curl --noproxy '*' -I --connect-timeout 5 --max-time 10 --resolve "play.googleapis.com:443:$address" https://play.googleapis.com/ >"$fallback" 2>&1 || true
    if https_responded "$fallback"; then
        printf '\nnamespace fallback (host curl/CA):\n' >>"$1"
        cat "$fallback" >>"$1"
        return 0
    fi
    return 1
}
android_dns_test() {
    timeout 8 sudo waydroid shell -- ping -c 1 -W 1 play.googleapis.com >"$LOG_DIR/network-dns-test.txt" 2>&1 || true
    dns_resolved "$LOG_DIR/network-dns-test.txt"
}
network_nat_present() {
    local ipt
    ipt="$(command -v iptables-legacy || command -v iptables || true)"
    if [[ -n "$ipt" ]] && sudo "$ipt" -w 3 -t nat -C POSTROUTING -s 192.168.240.0/24 '!' -d 192.168.240.0/24 -j MASQUERADE >/dev/null 2>&1; then return 0; fi
    # Arch can use Waydroid's native nft backend. Read its dedicated NAT chain.
    sudo nft list chain ip lxc postrouting 2>/dev/null | grep -qE 'ip saddr 192\.168\.240\.0/24 ip daddr != 192\.168\.240\.0/24.*masquerade'
}
android_default_route() {
    local route
    route="$(android_route)"
    if ! grep -qE '^default( |$)' <<<"$route"; then
        timeout 8 sudo waydroid shell -- ip -4 route add default via 192.168.240.1 dev eth0 || return 1
        route="$(android_route)"
    fi
    # A different default can indicate a VPN/custom network. Do not overwrite it.
    grep -qE '^default via 192\.168\.240\.1 dev eth0( |$)' <<<"$route"
}
network_check_and_repair() {
    local n route addr egress nat_ok=0 network_restarted=0
    msg 'Waydroidネットワークの確認'
    network_snapshot
    for n in $(seq 1 20); do
        addr="$(android_ipv4)"
        route="$(android_route)"
        android_has_ipv4 "$addr" && break
        sleep 1
    done
    if ! ip -4 -o addr show dev waydroid0 2>/dev/null | grep -q 'inet 192\.168\.240\.1/24' || ! android_has_ipv4 "$addr"; then
        warn 'waydroid0またはAndroid eth0のDHCP状態が不完全です。container/sessionを一度再起動します。'
        network_restart
        network_restarted=1
        network_snapshot
        addr="$(android_ipv4)"
        route="$(android_route)"
    fi
    android_has_ipv4 "$addr" || die 'Android eth0に192.168.240.0/24のIPv4がありません。DHCP/dnsmasq状態をnetwork-android.txtで確認してください。'
    if network_nat_present; then nat_ok=1; fi
    if (( nat_ok == 0 && network_restarted == 0 )); then
        warn 'Waydroid MASQUERADE ruleを確認できません。標準container networkを再生成します。'
        network_restart
        network_restarted=1
        network_snapshot
        route="$(android_route)"
        addr="$(android_ipv4)"
        android_has_ipv4 "$addr" || die 'ネットワーク再生成後もAndroid eth0にIPv4がありません。'
    fi
    network_nat_present || die '再生成後もWaydroid NATを確認できません。network-nftables.txtとnetwork-iptables-rules.txtを確認してください。'
    android_default_route || die '標準default routeを確認できません。既存の別gatewayは変更していません。'
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
    [[ "$(sudo sysctl -n net.ipv4.ip_forward)" == 1 ]] || die 'ホストのIPv4 forwardingが有効になりません。'
    if ! android_dns_test && (( network_restarted == 0 )); then
        warn 'Android DNS解決ができません。DHCP/DNSを再生成するためsession/containerを一度再起動します。'
        network_restart
        network_restarted=1
        network_snapshot
        route="$(android_route)"
        addr="$(android_ipv4)"
        android_has_ipv4 "$addr" || die 'DNS再生成後もAndroid eth0にIPv4がありません。'
        android_default_route || die 'DNS再生成後のdefault routeを確認できません。'
        sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
        android_dns_test || true
    fi

    # The Waydroid network helper installs DHCP/DNS INPUT, FORWARD and NAT
    # rules on each container start. Prefer a targeted UFW route rule only
    # when UFW is active and the Android side cannot reach an external IP.
    timeout 8 sudo waydroid shell -- ping -c 1 -W 3 1.1.1.1 >"$LOG_DIR/network-ip-test.txt" 2>&1 || true
    android_https_test "$LOG_DIR/network-https-test.txt" || true
    if dns_resolved "$LOG_DIR/network-dns-test.txt" && ! grep -qE 'bytes from|1 packets transmitted, 1 (packets )?received' "$LOG_DIR/network-ip-test.txt" && ! https_responded "$LOG_DIR/network-https-test.txt"; then
        egress="$(awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' "$LOG_DIR/network-host-egress.txt")"
        if command -v ufw >/dev/null && sudo env LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active' && [[ -n "$egress" ]]; then
            warn "UFW is active and external IPv4 failed; adding a scoped route exception waydroid0 -> $egress."
            sudo ufw route allow in on waydroid0 out on "$egress" from 192.168.240.0/24 comment 'MWI Waydroid forwarding'
            timeout 8 sudo waydroid shell -- ping -c 1 -W 3 1.1.1.1 >"$LOG_DIR/network-ip-test.txt" 2>&1 || true
            android_https_test "$LOG_DIR/network-https-test.txt" || true
        fi
    fi
    network_snapshot
    ip -4 -o addr show dev waydroid0 2>/dev/null | grep -q 'inet 192\.168\.240\.1/24' || die '最終確認でホストbridgeのIPv4が欠落しています。'
    network_nat_present || die '最終確認でWaydroid NATが欠落しています。'
    [[ "$(sudo sysctl -n net.ipv4.ip_forward)" == 1 ]] || die '最終確認でIPv4 forwardingが無効です。'
    if grep -qE 'bytes from|1 packets transmitted, 1 (packets )?received' "$LOG_DIR/network-ip-test.txt"; then
        ok 'Androidから外部IPv4へ到達できます。'
    else
        warn '外部IPv4への疎通を確認できません。iptables/nftablesの優先順位やFORWARD dropをログで確認してください。MWIは未知のnftables/firewalld rulesetを直接変更しません。'
    fi
    if dns_resolved "$LOG_DIR/network-dns-test.txt"; then
        ok 'Androidでplay.googleapis.comをDNS解決できました。'
    else
        warn 'Android DNS解決を確認できません。network-android.txtのDNS値とdnsmasq/53番の状態を確認してください。'
    fi
    if https_responded "$LOG_DIR/network-https-test.txt"; then
        ok 'Androidからplay.googleapis.comへのHTTPS応答を確認できました。'
    else
        warn 'Google Play APIへのHTTPS応答を確認できません。network-https-test.txtを確認してください。'
    fi
    network_regression_summary
    dns_resolved "$LOG_DIR/network-dns-test.txt" || die 'DNS疎通の検証に失敗しました。配置変更は完了していますが、導入成功とは判定しません。'
    https_responded "$LOG_DIR/network-https-test.txt" || die 'HTTPS応答を検証できません。Android側のHTTPSツール未対応の場合もこの段階で停止します。配置変更とバックアップは保持されています。'

}
network_regression_summary() {
    [[ -f "$LOG_DIR/network-baseline-android.txt" ]] || return 0
    local before=good after=good
    grep -qE 'default via 192\.168\.240\.1|default via' "$LOG_DIR/network-baseline-android.txt" || before=bad
    dns_resolved "$LOG_DIR/network-baseline-dns-test.txt" || before=bad
    https_responded "$LOG_DIR/network-baseline-https-test.txt" || before=bad
    grep -qE 'default via 192\.168\.240\.1|default via' "$LOG_DIR/network-android.txt" || after=bad
    dns_resolved "$LOG_DIR/network-dns-test.txt" || after=bad
    https_responded "$LOG_DIR/network-https-test.txt" || after=bad
    case "$before:$after" in
        good:good) printf '初回起動とMWI適用後のネットワーク: 両方OK（今回の処理では不通を再現せず）\n' | tee "$LOG_DIR/network-comparison.txt" ;;
        bad:good) printf '初回起動: 不通または未確定 / MWI適用後: OK（標準network再生成・route補完後に回復）\n' | tee "$LOG_DIR/network-comparison.txt" ;;
        good:bad) printf '初回起動: OK / MWI適用後: 不通または未確定（MWI後続処理での回帰を疑う）\n' | tee "$LOG_DIR/network-comparison.txt" ;;
        bad:bad) printf '初回起動とMWI適用後: 不通または未確定（Waydroid初期DHCP/Android netd/host firewallを優先調査）\n' | tee "$LOG_DIR/network-comparison.txt" ;;
    esac
}
boot_android11() {
    start_waydroid
    wait_android
    [[ "$(prop ro.build.version.release)" == 11 ]] || die '修復対象はAndroid 11です。既存イメージは置き換えていません。'
}
require_existing_android11() {
    # Broken translation/graphics may prevent Android from booting. Read the
    # base system image offline so repairs do not depend on a successful boot.
    local release=''
    if sudo systemctl is-active --quiet waydroid-container.service; then release="$(prop ro.build.version.release)"; fi
    if [[ -z "$release" ]]; then release="$(state_tool android-release-offline)"; fi
    [[ "$release" == 11 ]] || die "既存Androidは ${release:-未確認} です。A11を確認できないため修復を中止しました。"
}
install_android11() {
    download "$SYSTEM_URL" "$CACHE_DIR/$SYSTEM_ZIP"
    download "$VENDOR_URL" "$CACHE_DIR/$VENDOR_ZIP"
    sudo install -d -m 0755 "$IMAGE_DIR"
    state_tool extract-image "$CACHE_DIR/$SYSTEM_ZIP" "$IMAGE_DIR/system.img"
    state_tool extract-image "$CACHE_DIR/$VENDOR_ZIP" "$IMAGE_DIR/vendor.img"
    restore_selinux_contexts
    sha256sum "$CACHE_DIR/$SYSTEM_ZIP" "$CACHE_DIR/$VENDOR_ZIP" >"$LOG_DIR/images-SHA256SUMS"
    sudo waydroid init -f -i "$IMAGE_DIR" -s GAPPS
    boot_android11
    # Record the first Android 11 boot before Houdini or libnb,
    # or the later `waydroid upgrade -o` call. Comparing this with final checks
    # helps identify whether MWI's later stages introduced a network regression.
    ip -details addr show waydroid0 >"$LOG_DIR/network-baseline-host-interface.txt" 2>&1 || true
    ip route get 1.1.1.1 >"$LOG_DIR/network-baseline-host-egress.txt" 2>&1 || true
    sudo sysctl net.ipv4.ip_forward >"$LOG_DIR/network-baseline-ip-forward.txt" 2>&1 || true
    timeout 10 sudo waydroid shell -- sh -c 'ip -4 addr show dev eth0; ip -4 route; printf "net.dns1="; getprop net.dns1; printf "net.dns2="; getprop net.dns2' >"$LOG_DIR/network-baseline-android.txt" 2>&1 || true
    timeout 8 sudo waydroid shell -- ping -c 1 -W 3 1.1.1.1 >"$LOG_DIR/network-baseline-ip-test.txt" 2>&1 || true
    timeout 8 sudo waydroid shell -- ping -c 1 -W 1 play.googleapis.com >"$LOG_DIR/network-baseline-dns-test.txt" 2>&1 || true
    android_https_test "$LOG_DIR/network-baseline-https-test.txt" || true
    sudo waydroid shell -- pm path com.android.vending
}
download() {
    local url=$1 out=$2
    if [[ -s "$out" ]] && unzip -tq "$out" >/dev/null 2>&1; then return 0; fi
    curl -fL --retry 4 --connect-timeout 20 "$url" -o "$out.part"
    unzip -tq "$out.part" >/dev/null || die '取得ZIPが破損しています。'
    mv -- "$out.part" "$out"
}
prepare_waydroid_script() {
    if [[ ! -d "$PINNED_UPSTREAM/.git" ]]; then git clone "$WAYDROID_SCRIPT_REPO" "$PINNED_UPSTREAM"; fi
    [[ -z "$(git -C "$PINNED_UPSTREAM" status --porcelain --untracked-files=no)" ]] || die '固定commit用の上流コードに変更があります。'
    git -C "$PINNED_UPSTREAM" fetch --depth=1 origin "$WAYDROID_SCRIPT_COMMIT"
    git -C "$PINNED_UPSTREAM" checkout --detach "$WAYDROID_SCRIPT_COMMIT"
    [[ "$(git -C "$PINNED_UPSTREAM" rev-parse HEAD)" == "$WAYDROID_SCRIPT_COMMIT" ]] || die '上流commitが一致しません。'
    "$PYTHON_BIN" -m venv "$PINNED_UPSTREAM/venv"
    "$PINNED_UPSTREAM/venv/bin/python" -m pip install -r "$PINNED_UPSTREAM/requirements.txt"
}
repair_bridge() {
    prepare_waydroid_script
    stop_waydroid
    sudo env XDG_CACHE_HOME="$CACHE_DIR/upstream" PYTHONDONTWRITEBYTECODE=1 \
        "$PINNED_UPSTREAM/venv/bin/python" "$SCRIPT_DIR/lib/upstream_adapter.py" "$PINNED_UPSTREAM" -a 11 install libhoudini
    stop_waydroid
    state_tool verify-houdini "$CACHE_DIR/upstream/waydroid-script/downloads/libhoudini.zip"
    sudo install -D -m 0644 "$LIBNB32" /var/lib/waydroid/overlay/system/lib/libnb.so
    sudo install -D -m 0644 "$LIBNB64" /var/lib/waydroid/overlay/system/lib64/libnb.so
    state_tool set-props
    restore_selinux_contexts
}
verify_runtime() {
    sudo waydroid upgrade -o
    boot_android11
    state_tool check-installed
    state_tool verify-runtime
    state_tool check-network-policy
    [[ "$(prop ro.dalvik.vm.native.bridge)" == libnb.so ]] || die 'NativeBridge設定が反映されていません。'
    timeout 15 sudo waydroid shell -- dumpsys SurfaceFlinger >"$LOG_DIR/surfaceflinger.txt"
    grep -iE 'GLES:|GL_RENDERER|GL_VERSION' "$LOG_DIR/surfaceflinger.txt" || warn 'GPU名を取得できません。描画確認が必要です。'
    if grep -iE 'GLES:.*(llvmpipe|swiftshader|softpipe)' "$LOG_DIR/surfaceflinger.txt"; then die 'ソフトウェア描画を検出しました。GPU選択・描画設定の確認が必要です。'; fi
    network_check_and_repair
    systemctl --user is-active pipewire-pulse.socket pipewire-pulse.service >"$LOG_DIR/audio.txt" 2>&1 || warn '音声サービスは未確認です。実際の音声を確認してください。'
}
lifecycle_main() {
    case "${1:-}" in
        '') [[ "${RESET_WAYDROID:-0}" != 1 ]] || MODE=reset ;;
        --diagnose) MODE=diagnose ;; --install) MODE=install ;; --reset) MODE=reset ;;
        --repair|--repair-bridge) MODE=repair ;; --restore) MODE=restore; BACKUP="${2:-}"; [[ -n "$BACKUP" ]] || die '復元パスが必要です。' ;;
        --help|-h) printf 'MWI 0.2.2\n--diagnose / --install / --repair / --reset / --restore BACKUP\n'; return ;;
        *) die '不明な引数です。--help を参照してください。' ;;
    esac
    if [[ "$MODE" == restore ]]; then [[ $# == 2 ]] || die '引数が不正です。'; else [[ $# -le 1 ]] || die '引数が多すぎます。'; fi
    preflight
    diagnose
    if [[ "$MODE" == auto ]]; then
        if sudo test -d /var/lib/waydroid || [[ -e "$USER_DATA" ]] || sudo test -e "$IMAGE_DIR/system.img" || sudo test -e "$IMAGE_DIR/vendor.img"; then
            local answer
            [[ -t 0 ]] || die '既存環境があります。--diagnose または修復モードを指定してください。'
            printf '\n1: 診断のみ / 2: Houdini・libnb修復 / 3: 全環境退避して新規 / 0: 終了\n選択: '
            IFS= read -r answer || die '選択を読み取れません。'
            case "$answer" in 1) MODE=diagnose ;; 2) MODE=repair ;; 3) MODE=reset ;; 0) return ;; *) die '不明な選択です。' ;; esac
        else MODE=install; fi
    fi
    if [[ "$MODE" == diagnose ]]; then collect_logs; return 0; fi
    [[ "$HOST_FAMILY" == arch || "$HOST_FAMILY" == fedora ]] || die '変更操作はCachyOS/Archとdnf版Fedoraに対応します。rpm-ostree版は対象外です。'
    [[ "${XDG_SESSION_TYPE:-}" == wayland ]] || die 'Waylandにログインしてから実行してください。'
    if [[ "$MODE" == restore ]]; then
        state_tool inspect-backup "$BACKUP" "$UID"
        confirm '表示した対象をバックアップ時点に戻しますか（後日の対象変更も戻ります）' || die '復元を中止しました。'
        phase 'Waydroid停止' stop_waydroid
        phase '対象復元' state_tool restore "$BACKUP" "$UID"
        restore_selinux_contexts
        start_waydroid; wait_android
        printf '復元完了。ログ: %s\n' "$LOG_DIR"
        return
    fi
    if [[ "$MODE" == install ]]; then
        if sudo test -d /var/lib/waydroid || [[ -e "$USER_DATA" ]] || sudo test -e "$IMAGE_DIR/system.img" || sudo test -e "$IMAGE_DIR/vendor.img"; then die '既存環境があります。修復か --reset を選んでください。'; fi
    elif [[ "$MODE" == repair ]]; then
        sudo test -f /var/lib/waydroid/waydroid.cfg || die '設定がありません。初期化途中の場合は --reset で退避して再導入してください。'
        phase '既存Android版確認' require_existing_android11
    fi
    printf '\nモード=%s\n' "$MODE"
    if [[ "$MODE" == reset ]]; then
        printf '既存Waydroid・現在ユーザーのデータ・指定イメージを同じ親フォルダ内に退避し、新環境を作ります。\n新環境にゲーム・ログイン状態は引き継ぎません。元環境は削除しません。\n'
    elif [[ "$MODE" == repair ]]; then
        printf 'Houdini・libnbと関連設定をバックアップ後に差し替えます。ゲームデータは保持します。\n'
    else printf '指定Android 11/GApps + Houdini + 同梱test_libnbを導入します。\n'; fi
    printf 'ネットワーク安定化のため Waydroid の背景化動作を stop にします。背景化するとAndroid sessionが停止し、背景で動作中のアプリは終了します。設定は修復前バックアップから戻せます。\n'
    confirm 'この内容で続行しますか' || die '変更を中止しました。'
    phase 'ホスト準備' install_packages
    if [[ "$MODE" == reset ]]; then
        phase 'Waydroid停止' stop_waydroid
        phase '全環境退避' state_tool reset "$USER_DATA" "$UID" "$LOG_DIR/reset-paths.json"
    fi
    if [[ "$MODE" == install || "$MODE" == reset ]]; then
        phase 'Android 11初期化' install_android11
    fi
    phase 'Waydroid停止' stop_waydroid
    BACKUP="$(state_tool backup "$UID")"
    printf '修復前バックアップ: %s\n' "$BACKUP"
    phase 'ネットワーク安定化設定' state_tool set-network-policy
    state_tool enable-overlays
    phase 'Houdini/test_libnb差し替え' repair_bridge
    phase '配置・実行中Android確認' verify_runtime
    collect_logs
    printf '\n差し替え確認完了。ログ: %s\n復元: ./install.sh --restore %q\n' "$LOG_DIR" "$BACKUP"
    printf 'ミリシタの起動・FPS・音声は実際に確認してください。Google Play未認証時は端末登録が必要です。\n'
}
