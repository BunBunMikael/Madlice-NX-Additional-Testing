#!/usr/bin/env bash
# Puts the PC-made DKSH cache of every shader variant (tools/renut/precompile_all_variants.py) on the Switch's SD card,
# next to the NRO, over DBI's MTP responder (start DBI, choose "Run MTP responder", connect USB).
#
#   tools/send_shader_cache.sh [cache file]      default out/deko3d_shaders/deko3d_shaders.bin
#
# The console's own cache (sdmc:/switch/alice-nx/deko3d_shaders.bin) is copied to out/sd_backup/ first. Game data:
# the file stays on the PC's build tree and the SD card.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${1:-$root/out/deko3d_shaders/deko3d_shaders.bin}"
sd="mtp:/DBI MTP Responder/1: SD Card/switch/alice-nx"
[[ -f "$cache" ]] || { echo "no $cache: run tools/renut/precompile_all_variants.py first" >&2; exit 1; }
mkdir -p "$root/out/sd_backup"
stamp="$(date +%Y%m%d_%H%M%S)"
echo "== backing up the console's cache"
if kioclient5 copy "$sd/deko3d_shaders.bin" "file://$root/out/sd_backup/deko3d_shaders_$stamp.bin" 2>/dev/null; then
  ls -la "$root/out/sd_backup/deko3d_shaders_$stamp.bin"
else
  echo "   (none on the SD, or MTP not reachable: check that DBI's MTP responder runs)"
fi
echo "== copying $(du -h "$cache" | cut -f1) to the SD"
kioclient5 --overwrite copy "file://$cache" "$sd/deko3d_shaders.bin"
echo "== done: $sd/deko3d_shaders.bin"
