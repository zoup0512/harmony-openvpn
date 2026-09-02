# libovpnexec.so — OpenVPN3 core + NAPI glue, cross-compiled by the DevEco
# OHOS toolchain (externalNativeOptions in entry/build-profile.json5).
cmake_minimum_required(VERSION 3.16)
project(harmony_openvpn)

set(NATIVE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native)
set(OVPN3 ${NATIVE_ROOT}/third_party/openvpn3)
set(ASIO ${NATIVE_ROOT}/third_party/asio)
set(LZ4 ${NATIVE_ROOT}/third_party/lz4)
set(FMT ${NATIVE_ROOT}/third_party/fmt)
set(OSSL ${NATIVE_ROOT}/build/openssl-ohos/install)

file(GLOB LZ4_SRCS ${LZ4}/lib/*.c)

add_library(ovpnexec SHARED
    ovpn_napi.cpp
    ${OVPN3}/client/ovpncli.cpp
    ${OVPN3}/openvpn/openssl/xkey/xkey_provider.c
    ${OVPN3}/openvpn/openssl/xkey/xkey_helper.c
    ${LZ4_SRCS}
)

target_include_directories(ovpnexec PRIVATE
    ${OVPN3}
    ${OVPN3}/client
    ${ASIO}/asio/include
    ${FMT}/include
    ${LZ4}/lib
    ${OSSL}/include
)

target_compile_definitions(ovpnexec PRIVATE
    USE_OPENSSL
    USE_ASIO
    ASIO_STANDALONE
    USE_TUN_BUILDER
    HAVE_LZ4
    FMT_HEADER_ONLY
    OPENVPN_CORE_GIT_VERSION="harmony-openvpn-openvpn3"
    OPENVPN_ALLOW_INSECURE_CERTPROFILE
)

target_compile_options(ovpnexec PRIVATE
    -Wall
    -Wno-unused-parameter
    -Wno-sign-compare
    -Wno-deprecated-declarations
    -Wno-reorder
    -Wno-unknown-warning-option
    -ffunction-sections
    -fdata-sections
)

target_link_libraries(ovpnexec PUBLIC
    ${OSSL}/lib/libssl.a
    ${OSSL}/lib/libcrypto.a
    ace_napi.z
    hilog_ndk.z
)

target_link_options(ovpnexec PRIVATE -Wl,--gc-sections)

set_target_properties(ovpnexec PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)

# libfrpglue.so — NAPI bridge to the prebuilt Go frpc core shipped in
# entry/libs/arm64-v8a/libfrp_host.so (built by native/frpc-host/build-ohos.sh).
add_library(frpglue SHARED frp_napi.cpp)
target_link_libraries(frpglue PUBLIC ace_napi.z)
target_compile_options(frpglue PRIVATE -Wall -Wno-unused-parameter)
set_target_properties(frpglue PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
