#!/bin/bash
# Cross-compile OpenSSL 3.4.1 static libs for aarch64-linux-ohos using DevEco clang.
set -e
TC="$(cygpath -m "$(cygpath -d 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native')")"
ROOT="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
SRC="$ROOT/third_party/openssl"
OUT="$ROOT/build/openssl-ohos"
# Prefer make from PATH, else any locally installed Android NDK make.exe
# (a Windows-native make is required: MSYS make chokes on the drive-letter
# colon in the toolchain paths).
MAKE="$(command -v make || true)"
if [ -z "$MAKE" ]; then
    MAKE="$(ls /c/MyProgram/Sdk/Sdk/ndk/*/prebuilt/windows-x86_64/bin/make.exe \
        /c/Users/*/AppData/Local/Android/Sdk/ndk/*/prebuilt/windows-x86_64/bin/make.exe \
        /e/AndroidSdk/ndk/*/prebuilt/windows-x86_64/bin/make.exe 2>/dev/null | sort -V | tail -1)"
fi
if [ -z "$MAKE" ]; then
    echo "build-openssl.sh: no usable make.exe found (install one or add it to PATH)" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

export CC="$TC/llvm/bin/clang.exe --target=aarch64-linux-ohos --sysroot=$TC/sysroot"
export CFLAGS="-fPIC -O2"
export AR="$TC/llvm/bin/llvm-ar.exe"
export RANLIB="$TC/llvm/bin/llvm-ranlib.exe"
export PERL=$(which perl)
export PERL5LIB="$(cygpath -u "$ROOT")/perl_libs"
# stop MSYS from rewriting PERL5LIB into D:/... for the native make.exe
# (msys perl would then split it on the drive colon)
export MSYS2_ENV_CONV_EXCL="PERL5LIB"

perl "$SRC/Configure" linux-aarch64 no-shared no-tests no-docs no-apps no-legacy --prefix="$OUT/install" --libdir=lib

$MAKE -j8 build_libs
$MAKE install_dev
echo "OPENSSL_BUILD_OK"
