#!/usr/bin/env bash
set -Eeuo pipefail

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SELF/src/libnb_mwi.cpp"
TMP="$SELF/.build"

CLANG="${CLANG:-$(command -v clang || true)}"
CLANGXX="${CLANGXX:-$(command -v clang++ || true)}"
[[ -n "$CLANG" && -n "$CLANGXX" ]] || { echo "clang/clang++ required" >&2; exit 1; }

rm -rf "$TMP"
mkdir -p "$TMP/stubs32" "$TMP/stubs64" "$SELF/lib" "$SELF/lib64"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/stub.c" <<'STUB'
void __mwi_stub(void) {}
STUB

build_one() {
    local target="$1" stubdir="$2" out="$3"
    local lib
    for lib in libc libdl libm liblog; do
        "$CLANG" --target="$target" -nostdlib -shared -fPIC "$TMP/stub.c" \
            -Wl,-soname,"$lib.so" -o "$stubdir/$lib.so"
    done

    "$CLANGXX" --target="$target" -std=c++20 -fPIC -shared -nostdlib -fuse-ld=lld \
        -fno-exceptions -fno-rtti -fno-stack-protector \
        -fno-unwind-tables -fno-asynchronous-unwind-tables \
        -DLOG_DEBUG=1 -DSKIP_READABLE_CHECK=1 -DSKIP_NB_ENABLED_CHECK=1 \
        "$SRC" -L"$stubdir" \
        -Wl,--soname,libnb.so -Wl,--allow-shlib-undefined -Wl,--no-as-needed \
        -Wl,-rpath-link,"$stubdir" -llog -lm -ldl -lc \
        -o "$out"
}

build_one i686-linux-android30   "$TMP/stubs32" "$SELF/lib/libnb.so"
build_one x86_64-linux-android30 "$TMP/stubs64" "$SELF/lib64/libnb.so"

file "$SELF/lib/libnb.so" "$SELF/lib64/libnb.so"
sha256sum "$SELF/lib/libnb.so" "$SELF/lib64/libnb.so"
