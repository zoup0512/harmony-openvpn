#!/usr/bin/env bash
# Build libfrp_host.so (frpc core for HarmonyOS) and install it together with
# the android-log shim into the app's libs directory.
#
# Toolchain notes (verified on device):
# - GOOS=android is required. GOOS=linux c-shared builds crash on load:
#   Go's initial-exec TLS model conflicts with OHOS musl's dynamic TLS
#   (golang/go#54805). The android runtime path is the combination the
#   HarmonyOS community (SiYuan et al.) ships.
# - -tags netgo avoids net's cgo resolver, whose bionic-typed sources do not
#   compile against the musl sysroot.
# - The android runtime links -llog; ohos-libs/log.c provides that shim
#   because OHOS has no android liblog.
#
# Requirements: Go >= 1.24 on PATH (or GOROOT set) and the DevEco Studio OHOS
# SDK. Override the SDK location with DEVECO_SDK_DIR if it is not installed
# under "C:\Program Files".
set -euo pipefail

cd "$(dirname "$0")"

if [ -n "${DEVECO_SDK_DIR:-}" ]; then
  SDK="$(cygpath -d "$DEVECO_SDK_DIR" 2>/dev/null || echo "$DEVECO_SDK_DIR")"
else
  SDK='C:\PROGRA~1\Huawei\DEVECO~1\sdk\default\OPENHA~1'
fi
CLANG="$SDK/native/llvm/bin/clang.exe"
if [ ! -e "$CLANG" ]; then
  CLANG="$SDK/native/llvm/bin/clang"
fi
if [ ! -e "$CLANG" ]; then
  echo "OHOS SDK clang not found under $SDK (set DEVECO_SDK_DIR)" >&2
  exit 1
fi

export GOOS=android GOARCH=arm64 CGO_ENABLED=1
export CC="$CLANG --target=aarch64-linux-ohos --sysroot=$SDK\\native\\sysroot"
export CGO_LDFLAGS="-L$(pwd -W 2>/dev/null || pwd)/ohos-libs/arm64-v8a"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

"$CLANG" --target=aarch64-linux-ohos --sysroot="$SDK/native/sysroot" \
  -shared -fPIC -O2 -o ohos-libs/arm64-v8a/liblog.so ohos-libs/log.c

go build -tags netgo -buildmode=c-shared -trimpath -ldflags="-s -w" -o libfrp_host.so .

DEST_DIR="../../entry/libs/arm64-v8a"
mkdir -p "$DEST_DIR"
cp libfrp_host.so "$DEST_DIR/libfrp_host.so"
cp ohos-libs/arm64-v8a/liblog.so "$DEST_DIR/liblog.so"
echo "installed: libfrp_host.so + liblog.so ($(du -h libfrp_host.so | cut -f1))"
