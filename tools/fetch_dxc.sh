#!/usr/bin/env bash
# Installs Microsoft's DirectX Shader Compiler (official Linux release, checksum-pinned) where Renut's build looks for
# it: app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin/{bin,lib}/x64. The vendored XenosRecomp tree ships only DXC's
# headers there. Run once before building the host shaders (tools/build_sdk.sh does not need it; tools/host_shaders.sh does).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

dest="$root/app/thirdparty/reblue-XenosRecomp/thirdparty/dxc-bin"
url="https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/linux_dxc_2026_09_28.x86_x64.tar.gz"
sha256="96faadc7f5c282d2ffda49804beb4c3ee38127bc252b723234e3c5cdf7aa39a1"
[[ -d "$dest" ]] || { echo "Renut XenosRecomp dependency missing at $dest" >&2; exit 1; }
if [[ -x "$dest/bin/x64/dxc-linux" ]]; then
  echo "DXC already installed in $dest"
  exit 0
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/dxc.tar.gz" "$url"
echo "$sha256  $work/dxc.tar.gz" | sha256sum -c --quiet
mkdir -p "$work/x" "$dest/bin/x64" "$dest/lib/x64"
tar -xzf "$work/dxc.tar.gz" -C "$work/x"
cp "$work/x/bin/dxc" "$dest/bin/x64/dxc-linux"
cp "$work/x/lib/libdxcompiler.so" "$work/x/lib/libdxil.so" "$dest/lib/x64/"
cp "$work/x/LICENSE-MS.txt" "$work/x/LICENSE-LLVM.txt" "$dest/"
LD_LIBRARY_PATH="$dest/lib/x64" "$dest/bin/x64/dxc-linux" --version
echo "DXC installed in $dest"
