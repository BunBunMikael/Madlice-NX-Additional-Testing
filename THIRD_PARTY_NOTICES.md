# Third-party notices and credits

This project is a port made with other people's work. None of it would exist without them.

## ReXGlue SDK

- Project: https://github.com/rexglue/rexglue-sdk
- Role: the static recompiler that translates the game's Xbox 360 PowerPC code to C++, and the runtime it runs on
  (kernel, filesystem, input, audio, and the emulated Xenos GPU used by this build).
- Used as: the updated SDK source vendored in `sdk/`, taken from the Renut NX Ultimate base and built from source.
- ReXGlue builds on the Xenia Xbox 360 emulator (https://github.com/xenia-project) and was inspired by XenonRecomp
  (https://github.com/hedge-dev/XenonRecomp) and rexdex's recompiler (https://github.com/rexdex/recompiler).

Its license (BSD 3-Clause), as it appears in the SDK:

```
Copyright (c) 2026, Tom Clay <tomc@tctechstuff.com>

Portions of this software are derived from the Xenia project:
Copyright (c) 2022, Ben Vanik and Xenia project contributors
https://xenia.jp

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## sa2-nx

- Project: https://github.com/ChanseyIsTheBest/sa2-nx (GPL-3.0), the Nintendo Switch port of Sonic Adventure 2.
- Role:
  - its porting prompt and porting guide: this port followed their method, stage by stage;
  - the initial SDK fork and Switch platform / Renut integration used by earlier revisions of Alice;
  - selected adapted tools and game-integration files that remain in this repository. The current SDK and renderer
    dependencies are vendored from Renut NX Ultimate as described below.
- Because of that copied and adapted code, this project is distributed under the GPL-3.0 as well (see `LICENSE`).

## Renut's renderer (reNut, banjo-nx, Renut NX Ultimate)

- `app/src/renut_engine/gpu`, `app/thirdparty/plume`, `app/thirdparty/reblue-XenosRecomp`, `app/thirdparty/uam` and
  `sdk/` contain the updated Renut renderer, its deko3d backend, shader translator, shader compiler and ReXGlue SDK
  vendored from Renut NX Ultimate. Their individual upstream licences and notices remain in their source directories.
- `app/src/cpu/sa2_enhancements.*`, `app/src/me/sa2_render_mode.*` and `app/src/me/me_platform_compat.h` are sa2-nx's
  files, taken as they are (GPL-3.0).
- The renderer dependencies are now included in this repository rather than fetched from a neighbouring sa2-nx tree.
  The build still downloads the official Linux DirectX Shader Compiler release into the ignored build/dependency area.

## gears2-nx

- Project: https://github.com/VasilkovND/gears2-nx (GPL-3.0), the Nintendo Switch port of Gears of War 2 (UE3).
- `tools/renut/ue3_extract_shaders.cpp` is a modified copy of its `shaders/gow2_extract_shaders.cpp` (at commit
  3033a796): the shader extraction from cooked UE3 packages, adapted to Alice's file version 690 and its compressed
  shader code (the changes are listed at its top). It builds with the vendored SDK's **libmspack** (LGPL-2.1) and **xxHash** (BSD-2-Clause).

## Switch build tools

- **deko3d**, **libnx** and devkitA64 from devkitPro (installed separately).
- **SPIRV-Cross** (KhronosGroup, Apache-2.0), tag vulkan-sdk-1.4.363.0, built by `tools/deko3d_build_tools.sh`.
- **uam** (zlib; SwitchWakerHD's patched 1.1.0), built from the vendored `app/thirdparty/uam`.
- The current `tools/renut/deko3d_*.py` shader conversion, optimisation, packaging and cache tools are vendored from
  Renut NX Ultimate (with Alice's Linux paths); their upstream GPL-3.0 lineage and source-port notices remain in their
  headers. `tools/check_switch_build.py` and other retained helper tools are adapted from sa2-nx and related ports.

## Game

Alice: Madness Returns (developed by Spicy Horse, published by Electronic Arts; a trademark of Electronic Arts Inc.)
is not part of this repository, in any form. See the disclaimer in `README.md`. The homebrew menu
icon is made at build time from the player's own disc (`tools/disc_icon.py`) and is not in this repository; the
fallback icon (`app/switch/icon.jpg`, drawn by `tools/make_icon.py`) is original artwork, with no art from the game
or its publisher.
