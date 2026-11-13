#!/usr/bin/env bash
# Every Xenos shader container in the game's cooked packages, into the PC capture folder the build reads
# (out/pc/shader_capture, merged into out/renut_shader_dump at configure): no playing needed to find shaders
# (docs/alice-notes.md, "Every shader from the game's packages"). Game data: out/ only, never committed.
#
#   tools/renut/extract_shaders.sh          (then: tools/host_shaders.sh, switch_shaders.sh, ...)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
sa2="${SA2_NX:-$root/../sa2-nx}"
mspack="$sa2/sdk/thirdparty/libmspack/libmspack/mspack"
bin="$root/out/tools"
mkdir -p "$bin"
cc -O2 -c -I"$mspack" "$mspack/lzxd.c" -o "$bin/lzxd.o"
cc -O2 -c -I"$mspack" "$mspack/system.c" -o "$bin/mspack_system.o"
c++ -std=c++20 -O2 -I"$mspack" -I"$sa2/sdk/thirdparty/xxHash" "$root/tools/renut/ue3_extract_shaders.cpp" \
  "$bin/lzxd.o" "$bin/mspack_system.o" -o "$bin/ue3_extract_shaders"
set +e
"$bin/ue3_extract_shaders" "$root/out/shaders_extracted" "$root/assets/game_root/AliceGame" \
  "$root/assets/game_root/Engine" > "$root/out/shaders_extracted.log" 2> "$root/out/shaders_extracted.err"
code=$?
set -e
tail -n 1 "$root/out/shaders_extracted.log"
# Exit 2 means some chunks did not decode (listed in out/shaders_extracted.err); what did decode is still written.
[[ $code -eq 0 || $code -eq 2 ]] || exit $code
mkdir -p "$root/out/pc/shader_capture"
cp -n "$root/out/shaders_extracted/"*.bin "$root/out/pc/shader_capture/"
echo "$(ls "$root/out/pc/shader_capture" | wc -l) shaders in out/pc/shader_capture"
