#!/usr/bin/env bash
# Builds prov_harness from an ESP-IDF v5.3 checkout (needs the mbedtls and
# protobuf-c submodules) for the app's provisioning interop tests.
#   IDF_PATH=~/esp/esp-idf app/tool/prov_harness/build.sh [out_dir]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
idf="${IDF_PATH:?set IDF_PATH to an ESP-IDF v5.3 checkout}"
out="${1:-$here/build}"
c="$idf/components"
mkdir -p "$out"

if [ ! -f "$out/mbedtls/library/libmbedcrypto.a" ]; then
    cmake -S "$c/mbedtls/mbedtls" -B "$out/mbedtls" -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF \
        -DCMAKE_BUILD_TYPE=Release > "$out/mbedtls-configure.log"
    cmake --build "$out/mbedtls" -j --target mbedcrypto > "$out/mbedtls-build.log"
fi

cc -O1 -g -std=gnu17 -w -DCONFIG_ESP_PROTOCOMM_SUPPORT_SECURITY_VERSION_1=1 \
    -I"$here/stubs" \
    -I"$c/protocomm/include/common" -I"$c/protocomm/include/security" -I"$c/protocomm/src/common" \
    -I"$c/protocomm/proto-c" -I"$c/wifi_provisioning/include" -I"$c/wifi_provisioning/proto-c" \
    -I"$c/protobuf-c/protobuf-c" -I"$c/mbedtls/mbedtls/include" \
    "$here/harness.c" \
    "$c/protocomm/src/common/protocomm.c" "$c/protocomm/src/security/security1.c" \
    "$c/protocomm/proto-c/constants.pb-c.c" "$c/protocomm/proto-c/session.pb-c.c" \
    "$c/protocomm/proto-c/sec0.pb-c.c" "$c/protocomm/proto-c/sec1.pb-c.c" "$c/protocomm/proto-c/sec2.pb-c.c" \
    "$c/wifi_provisioning/src/wifi_config.c" "$c/wifi_provisioning/src/wifi_scan.c" \
    "$c/wifi_provisioning/proto-c/wifi_constants.pb-c.c" "$c/wifi_provisioning/proto-c/wifi_config.pb-c.c" \
    "$c/wifi_provisioning/proto-c/wifi_scan.pb-c.c" \
    "$c/protobuf-c/protobuf-c/protobuf-c/protobuf-c.c" \
    "$out/mbedtls/library/libmbedcrypto.a" \
    -o "$out/prov_harness"
echo "built $out/prov_harness"
