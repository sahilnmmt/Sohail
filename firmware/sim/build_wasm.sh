#!/usr/bin/env bash
# Builds the browser preview's WebAssembly module from the real firmware core.
# Needs zig (pip install ziglang) for its bundled wasm32-wasi libc.
#   firmware/sim/build_wasm.sh [out_dir]      (default: firmware/sim/web)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../components/sohail_core"
out="${1:-$here/web}"
work="${TMPDIR:-/tmp}/sohail-wasm"
zig="${ZIG:-$(command -v zig || python3 -c 'import ziglang, os; print(os.path.join(os.path.dirname(ziglang.__file__), "zig"))')}"

mkdir -p "$work" "$out"
if [ ! -f "$work/cJSON/cJSON.c" ]; then
    git -c advice.detachedHead=false clone -q --depth 1 --branch v1.7.18 https://github.com/DaveGamble/cJSON.git "$work/cJSON"
fi

"$zig" cc -target wasm32-wasi -mexec-model=reactor -O2 -Wall -Wextra -Wno-unused-parameter \
    -I"$core/include" -I"$work/cJSON" \
    "$core"/src/*.c "$work/cJSON/cJSON.c" "$here/sim.c" "$here/wasm_api.c" \
    -s -o "$out/sohail.wasm"
echo "wrote $out/sohail.wasm ($(wc -c < "$out/sohail.wasm") bytes)"
