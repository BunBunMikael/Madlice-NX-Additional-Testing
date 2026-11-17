#!/usr/bin/env bash
# Translates Default.xex to C++ with the in-tree ReXGlue host code generator.
#
#   tools/codegen.sh [extra rexglue codegen options, e.g. --ignore-stamp]
#
# The codegen flavour is app/codegen_flavor.toml. Then tools/post_codegen.py records the flavour's name.
#
# Input:   assets/game_root/Default.xex, app/alice_manifest.toml
# Output:  app/generated/ (not committed), out/codegen.log, out/default_image.bin (the decrypted image)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$root/sdk"
rexglue="${REXGLUE:-$sdk/out/linux-amd64/rexglue}"
[[ -x "$rexglue" ]] || { echo "rexglue not found at $rexglue; build it first" >&2; exit 1; }
mkdir -p "$root/out"
export REX_MAX_JUMP_TABLE_ENTRIES=1024
export REXGLUE_DUMP_IMAGE="$root/out/default_image.bin"
cd "$root/app"
set +e
"$rexglue" codegen alice_manifest.toml "$@" > "$root/out/codegen.log" 2>&1
code=$?
set -e
tail -n 30 "$root/out/codegen.log"
[[ $code -eq 0 ]] || exit $code
REXSDK_DIR="$sdk" python3 "$root/tools/post_codegen.py"
