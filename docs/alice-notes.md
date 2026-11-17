# Alice: Madness Returns (Xbox 360): analysis notes

Facts about the game's code and data that the port depends on, each with where it came from. Addresses are guest
addresses in `Default.xex` (image base 0x82000000).

## Stage 1: the disc (2026-11-02)

| What | Value | Evidence |
|---|---|---|
| Title ID | 45410916 | `rexglue codegen` header (out/codegen.log) |
| Media ID | 31C4B45C | same |
| XEX version | 0.0.0.2 | same |
| Build time | 2011-04-27 02:56:13 UTC | same |
| Original name | `AliceGame-XeReleaseLTCG.pe` | XEX optional header 0x000183FF |
| Image | 0x82000000 + 0x1460000 | codegen (`out/default_image.bin`) |
| Entry point | 0x82DCFAC0 | XEX optional header 0x00010100 |
| Imports | xboxkrnl.exe, xam.xex only | XEX import libraries (0x000103FF) |
| XDK | 2.0.20353 (D3D9LTCG 2.0.20353.16385, XAUDIO2, XONLINE, XHV2, XMP, D3DX9) | XEX static libraries (0x000200FF) |
| Compiler | MSVC 16.0.11886 / 16.0.10224, LINK 10.0.11886 | same |
| Engine | Unreal Engine 3 (cooked for Xenon: `CookedXenon`, package tag 0x9E2A83C1) | the data |

**No guest DLLs.** The executable imports only xboxkrnl and xam, and no other file on the disc starts with `XEX2`
(scan of every file over 4 KB). There's no XEX2 header in the image either.

**Data** (4.5 GB, 1952 files):
- `AliceGame/CookedXenon`: 1654 `.xxx` packages, four texture file caches (`Textures.tfc`, `CharTextures.tfc`,
  `WorldTextures.tfc`, `Lighting.tfc`), `GlobalShaderCache-Xbox360.bin` (tag `GSMB`, uncompressed), `Coalesced_*.bin`
  (ini files, six languages) and `GlobalPersistentCookerData.upk`.
- The packages are compressed as whole files: each starts with the UE3 chunk header (0x9E2A83C1, block size 0x20000,
  then compressed/uncompressed sizes and a size pair per block). A `.uncompressed_size` file sits beside 13 of them.
  The blocks don't start like zlib (0x78) or LZO, so they're most likely LZX (XMemCompress). That isn't confirmed yet,
  and it only matters for offline shader extraction (masseffect-nx's `ue3_shader_scan` handles LZO only). At run time,
  the game's own translated code decompresses them.
- `AliceGame/Movies`: Bink movies (`.bik`) with subtitle `.txt` files. Bink is linked into the executable, so it's
  translated with the rest of the code.

## Stage 2: code generation

- Codegen: ~310 s single-threaded, 479 files, 247 MB of C++ (Monster High: 144 MB).
- First validation: 3 "target not in any function", fixed in `app/overrides.toml` (evidence there).
- `setjmp` 0x82DBA170 / `longjmp` 0x82DBA440: found by shape (the only `stfd f14,0(r3)` and the only
  `lfd f14,0(rX)` in the image), the same CRT pair and jmp_buf layout as Monster High's. setjmp: hook check (lis r4
  / lwz r0,3404(r4) / mtctr / bnectr), mflr r0, mfcr r4, stfd f14-f31 at 0-136(r3), std r13-r31 from 152(r3).
  longjmp: mflr r0, stwu r1,-80(r1), mr r7,r3, val==0 check, then the mirror loads lfd f14.. from 0(r7).

## Renderer route: what the UE3 ports teach (read 2026-11-02, not yet checked on Alice)

- gears2-nx `gow2/PORTING.md`: "Unreal does not create shaders through Direct3D: only 7 shader objects are ever
  created; the rest are loaded straight from the packages." Its draws are matched to a shader library by their
  microcode, and the library is extracted offline from the cooked packages, which are LZX on that disc.
- This is why Monster High's Renut route (shaders captured at CreateVertexShader/CreatePixelShader) probably fits
  Alice badly. Mass Effect, also UE3, used the PM4-ring renderer (sa2-nx `app/src/me`) with offline package scanning
  (`ue3_shader_scan`, LZO only). For Alice that scanner needs an LZX decoder (libmspack is in the SDK's thirdparty).
  To confirm on Alice: count the CreateVertexShader/CreatePixelShader calls in a boot.
- Other UE3 lessons from Gears 2 to expect here:
  - UnrealScript and the game thread dominate the CPU, so a CPU overclock is likely needed on Switch.
  - Occlusion queries are polled by the render thread.
  - The depth prepass vs the base pass need bit-identical depth.
  - 7e3 render targets with an exponent bias.
- `tools/pointer_fixpoint.py` (2026-11-02): pass 1 found 27,848 gaps and 176 candidates. 160 were accepted, and 16
  were rejected (13 no code, 2 tail branches into a function body, 1 with no terminator). Pass 2 found nothing new.
- `switch_check.py` (code 0x82250000-0x8306CBA8): 0 truncated, 0 wrong, 0 missed. 17 "odd shapes" are UnrealScript's
  bytecode dispatch, not switches. At 0x822E50A8 and the run of 16 stubs at 0x822F3438-0x822F3728 (one every 0x30
  bytes), each does `lwz r11,24(r4)` (the script stack's Code pointer), `lbz` the opcode, stores Code+1, then
  `lwzx`s a 256-entry function table in data (0x833370F0, then 0x833374F0 onward, 0x400 apart) and tail-calls it
  with `bctr`. They're generated as indirect calls, which is right. The tables are filled at run time, so a native
  whose address only appears there would surface at boot as "unregistered function".

## Stage 3: first boots on PC, emulated GPU (2026-11-02)

The first build (`tools/build_pc.sh -j 4`, Renut off) booted on its first run, with no fatal error, no unregistered
call and no access violation in any test so far (up to 8 minutes).
- Boot to the Spicy Horse logo, the "Press START" title, the main menu, difficulty select, the gamma and invert-look
  screens of a new game, and the opening cinematic with subtitles. Audio (XMA) decodes in real time, and the
  presenter acquires 99.9 % of frames without waiting.
- `tools/boot_test.sh` runs with `--alice_screenshots` and `--input_script`. The menus' timing changes between runs,
  so a fixed script can land in a different menu. One run reached the "Memories" screen (Bumby, 0/16 memories) after
  START during or after the cinematic.
- Every warning in the log is a normal existence probe: optional subtitle `.txt` and `.xxx` files beside the movies,
  `*TextureS.xxx` beside the `.tfc` caches, localized TOCs (POL/RUS/SLO), `Binaries\EpicInternal.txt`, and the
  `UPDATE:` device (no title update installed).
- 20-minute run (2026-11-02, census build, scripted input): no fatal error, no unregistered call, no access violation.
  The first ~8 minutes were movement, jumps and attacks in the orphanage (hallway and dormitory). After that, an A
  press examined a drawing on the wall, which opens a text popup that only B closes, and the input loop sends no B. So
  the rest of the run sat on that popup with the game running. Wider coverage (Wonderland, combat, saving and loading)
  needs a person playing, or a smarter script.

## Switch build without a renderer (2026-11-02)

- `ALICE_RENUT=OFF tools/build_switch.sh -j 4`: the whole game compiles and links for the console (out/nx/alice.nro,
  76 MB; 46 minutes on 8 cores at -j 4). It has no renderer, so on a console it can't show anything yet. It only
  proves the translated code builds for aarch64 with devkitA64.
- In stock Ryujinx (Ryubing 1.3.3, flatpak), the NRO starts: it reaches the SDK's Switch layer (docked mode, 1920x1080)
  and maps the guest memory arena. Then committing guest memory fails (`AllocFixed: could not commit ... Failure
  0x0000E401`), and the first guest access is an invalid memory access. sa2-nx's deko3d guide tested in **banjo-nx's
  Ryujinx build**, with its three no-loader SDK changes, so stock Ryujinx doesn't seem to support the SDK's memory
  commit. Not a sign of a bug in the port. A real console, or that Ryujinx build, is needed.
- The test copy is in Ryujinx's own SD folder, `~/.var/app/io.github.ryubing.Ryujinx/config/Ryujinx/sdcard/switch/alice-nx`
  (alice.nro, alice.toml without the asset pack, and game_root as a link to disc/). It's local only and holds the
  game's translated code, so don't share it.

### On a real Switch (2026-11-02, renderer off)

Sent with `tools/send_switch.sh` to `sdmc:/switch/alice-nx/alice.nro`, game files in `sdmc:/switch/alice-nx/game_root/`.
From its log (`sdmc:/switch/alice-nx/logs/alice_001.log`):
- The guest memory arena maps (`Guest memory arena mapped: virtual base 0x...576754C000`): the 0xE401 commit failure
  seen in stock Ryujinx doesn't happen on hardware.
- No asset pack: "the game data is 4535 MB, over FAT32's 4 GB file limit". It falls back to the game folder: 1960
  entries mounted in 5978 ms (the VFS index written to `cache/` speeds up later starts).
- The game's code starts: function table initialised, audio up (48000 Hz, 2 channels).
- Then `VdInitializeRingBuffer: no GPU emulation loaded; call ignored`, and nothing more logged: with Renut off there
  is no GPU, so the first wait on a GPU fence never ends. A black screen, by design for this build. Next: Renut.
- To do: the pack's 4 GB limit (FAT32). Split the pack, or leave the movies out of it.

## Stage 4: Renut on PC (2026-11-02)

The hooks are retargeted and rewritten for Alice's LTCG Direct3D (docs/d3d-census.md, "Renut's hooks for Alice").
Built with `ALICE_RENUT=ON tools/build_pc.sh`, run with `--sa2_renderer=renut --renut_gpu_backend=vulkan`.

- Two runs capture the shaders: the first met 176, the second 117 more (293 in out/pc/shader_capture/); each
  rebuild translates them. With all of them built, nothing is "not in the shader cache".
- UE3's rendering thread hung in `sub_82B4D048` (IDirect3DQuery9::GetData, found with a gdb backtrace of every
  thread: the guest functions are host symbols): occlusion queries (type 9) wait for counts the GPU writes into the
  query's memory. Hooked: an issued occlusion query answers "every sample passed", a screen extent query zeros.
- After that: 200 s with no hang, 30.00 fps, about 32,800 draws a second at the menu (all drawn: depth prepass, UI),
  resolves and targets as expected (`--banjo_renut_diag_resolve_trace=true`: the scene at 1280x720, the bloom chain
  down to 1x1, the final resolve of the back buffer 400007C0 into the front buffer texture 40001970 that Swap shows).
- **The picture is black**: every screenshot's pixels are 0, at 20 s (the intro movie) as at the menu. Ruled out:
  the scan-out gamma ramp (`--sa2_renut_gamma_ramp=false`), the snapshot deltas (`--sa2_renut_snapshot_deltas=false`),
  the minimized window (Renut's capture draws offscreen), the no-hardware flag (Alice's Direct3D never tests it), the
  viewport (Alice's SetViewport writes the PA_CL_VPORT floats at 10504-10524). The Vulkan validation layer is not
  installed here. Next: find where the colour is lost (a draw's output, a resolve, or the present), e.g. by reading a
  render target back after a known draw.

### The black picture, found and fixed (2026-11-02)

Narrowed down step by step, with temporary diagnostics (removed afterwards):
- **The present is fine.** Swap's front buffer 40001970 has its host texture every frame (1280x720, slot 3, written
  by a resolve). Presenting a disc-loaded texture instead (a movie plane, R8_UNORM) showed its values (11, and 16 =
  video black), not 0. So the scan-out and the capture work.
- **Clears, resolves and the front buffer are fine.** With every colour clear in `ClearTargets` forced to magenta,
  the front buffer and the 322x182 target 422A6CC0 came out **solid magenta**: not one pixel of any draw landed,
  not even unblended draws with colour mask F. (Forcing only the resolve-and-clear path changed nothing: the game's
  colour clears don't go through it.)
- **The draws had no vertices.** No `[streamdump]` line for any draw: the host layout's stream mask was 0. A log of
  the draws' declarations showed device +12120 = **0** for 20 of 21 (declaration, shader) pairs, with `NoDeclaration()`
  (0 elements) as the fallback, although the shaders have inputs. Every vertex read the zero stream.
- **Cause:** UE3's RHISetBoundShaderState `82A51520` normally stores a null declaration and sets a vertex shader that
  D3DVertexShader_Bind already patched for the state's declaration (d3d-census.md, last section). Bind is inlined
  under LTCG, so Renut never saw it, and the shader captured at registration has unpatched fetches.
- **Fix:** hook `82A51520`. The bound shader (`[[state+4]+0]+8`) gets the state's declaration (`[state+0]`) as its
  `bound_declaration`, queued to the render thread only when the pairing changes. After it, every logged pair had
  elements (22 of 22), and the frames have colour: the logos, the title screen and the menu, and gameplay in the
  orphanage, at 30.00 fps.

### The overexposed scene: the resolve exponent bias (2026-11-02)

With the vertices fixed, the 3D scene (menu Alice, the orphanage) came out far brighter than on the emulated GPU,
while the UI was right. The HDR scene resolves pass flags F4000000: D3DRESOLVE_EXPONENTBIAS −3 (bits 26-31), so the
hardware writes the colour / 8. Renut copied the bits. Now a resolve with a bias is drawn through `resolve_copy_ps`
with `param0` = 2^bias, on every backend. If the drawn copy isn't possible (different formats, multisampled), it
logs a warning and copies as before; no such warning came up in the test runs.

Same input script on both renderers (`60:START,75:A,90:START,105:A,118:A`, shots at 70/100/130/160 s): the same
screens, at the same moments. **Still different:** Renut's picture is somewhat brighter and less saturated than the
emulated GPU's. The menu's teal grading is missing, and the orphanage is lighter. Next candidates: the colour
grading (a volume-texture LUT?), the gamma render-target formats (8_8_8_8_GAMMA), the display ramp.

### On a real Switch with Renut (2026-11-02, first run)

`ALICE_RENUT=ON tools/build_switch.sh` (80.9 MB NRO; the first try relinked the no-renderer NRO, since the script
only took ALICE_RENUT at the first configure: fixed in 60cf91b), 293 shaders from the PC captures, handheld,
1280x720. Log: out/nxlink.log (5 minutes of it, until the listener's time limit).
- **What the user saw:** the menu and the movies are right; the game runs, about 24 fps in the first gameplay scene,
  textures good. Wrong: the Doctor and a door all black, Charlie's and Alice's eyes missing, some children too dark,
  glitches in the light shafts through the windows.
- **From the log:** no error, fault or lost device; no exponent-bias warning. 30 fps early on (GPU ~1.4 ms a
  frame), 12-17 fps in the 10 s windows later (GPU 24-28 ms, render thread 12-33 ms a frame), and drops to 9-10 fps
  while uam compiled 178 variants (180 ms each, then kept in `deko3d_shaders.bin`).
- **49 shaders not in the cache** (`Shader ... is not in the shader cache: captured to /switch/alice-nx/shader_capture/`):
  their draws are skipped, the likely cause of the black and missing parts. Copied over DBI's MTP with `kioclient5`
  (`mtp:/DBI MTP Responder/1: SD Card/switch/alice-nx/shader_capture/`) into out/pc/shader_capture: 342 in all.

### Second console run, 342 shaders (2026-11-02)

- 4 shaders still missing (was 49), no error. DKSH cache 178 hits, 62 new uam compiles.
- 28-30 fps in the menus and movies; gameplay mostly **15-18 fps** (dips to 9-12), with the GPU at 21-25 ms and the
  render thread at 9-12 ms of a ~59 ms frame. So the limit is the game's own threads (the translated code), not the
  renderer.
- The user saw: no New Game in the menu (only Continue: there's a save). In the hub, a child with only a head (body
  missing); glitchy textures on the floor and in the light shafts; a big jump in brightness on going outside.
- Clocks: the game held the GPU at 768 MHz and the memory at 1600, but left the **CPU at stock** (the log names no
  CPU clock). gears2-nx (UE3) measured 12-17 fps at stock, 24-27 at CPU 1785 MHz: its game thread is 80-90 % busy.
  Now `alice_cpu_mhz` (default 1785, the user's call; 0 = untouched) holds the CPU at 1785 in both modes and puts
  the start rate back at exit (`app/src/cpu/alice_handheld_clocks.cpp`).
- The build runs the **classic** codegen (`(classic codegen)` in the first log line): none of sa2-nx's CPU passes
  (`tools/post_codegen.py`, the optimised flavour: registers as locals in loops and leaves, direct calls, read-only
  constants, ...). gears2-nx's `gow2/CPU_OPTIMIZATION.md` got its game thread out of the way with registers kept in
  host registers between calls. Next big CPU step, to be checked on PC before the console.

### Every shader from the game's packages (2026-11-02)

`tools/renut/ue3_extract_shaders.cpp` (gears2-nx's `gow2_extract_shaders.cpp`, adapted; build line at its use in
`tools/renut/extract_shaders.sh`) reads every cooked package and writes each Xenos container once, named by XXH3 as
Renut's capture does (`{vs,ps}_<xxh3>.bin`).
- Alice's packages: UE3 file version 690 (licensee 0, engine 6759, cooker 107), chunk compressed, CompressionFlags 4
  (LZX, XMemCompress framing, window 2^17). The summary has four more words than Gears' 575 between DependsOffset and
  the GUID: with them, AliceEntryExtra.xxx's first chunk is at compressed offset 749, where its tag is. Blocks whose
  compressed size equals the uncompressed size are stored raw (88 failed as LZX before).
- Where the shaders are: `GlobalShaderCache-Xbox360.bin` (GSMB, plain) has 241 containers as they are; the map
  packages' **SeekFreeShaderCache** holds the material shaders in compressed chunks: u32 uncompressed size, u32
  compressed size, an LZX stream (Chapter1_W2_ASSEM_01_S.xxx: 90 chunks of 3-23 containers each, 467 shaders).
- Whole game (1,949 files, 17 minutes): 63,601 code chunks, **29,701 distinct shaders** (28,454 pixel, 1,247
  vertex; 117 MB). **All 367 shaders captured by playing are among them**, byte for byte. Not decoded: the first
  chunk of Chapter1_W2_CP_World.xxx and 6 chunks of other packages (LZX error 11 or 3): a few shaders may still be
  missed; the runtime capture stays as the fallback.
- Cost (a sample of 1,000): XenosRecomp 118 s, GLSL passes with uam checks 69 s, GLSL package 1.3 MB. On the Switch
  the GLSL package is decompressed per shader (zstd dictionary), and the SPIR-V cache isn't used.

### Third console run: every shader, CPU at 1785 MHz (2026-11-03)

`out/nx/alice.nro` (151 MB, 29,701 shaders), handheld 1280x720. Log: out/nxlink.log (12:15-12:21, until the
listener's time limit).
- Clocks: `[clocks] CPU 1785 MHz held (it was 1020.0)`; GPU 768 MHz.
- **0 shaders missing** (no "not in the shader cache" line); uam 68 compiles, 0 failed; DKSH cache 187 hits.
- fps per 10 s window: movies/menu 30 (GPU 1.4 ms); orphanage and streets **26-30 fps** (GPU 20-36 ms; was 15-18
  before the CPU clock). Then a load window (13.5 fps, ~12:20:30), and after it **~21 fps with the GPU at 45-52 ms**,
  render thread ~9 ms: GPU-bound.
- **What the user saw:** textures good until the rooftop of one of the buildings; there everything turns white, and
  Alice too once she steps into it. That is where the GPU time doubles. Likely the "brightness jump going outside"
  from the second run, gone to the end: NaN/Inf or a runaway value in the HDR scene / eye adaptation, spread by bloom
  and the tonemap. Next: reproduce on PC (Renut, Vulkan) from the console's checkpoint save
  (`sdmc:/switch/alice-nx/alice/B13EBABEBABEBABE/45410916/00000001/Alice2Checkpoint.sav`, the same layout as
  `~/.local/share/alice/...` on PC).

### 720p in both modes, shadows off (2026-11-03, the user's request)

- **720p:** handheld already rendered at 1280x720. Docked rendered at `sa2_render_height_docked = 1080` (set in
  `BuiltInConfig`, `app/src/alice_app.h`, and the cvar's default in `app/src/me/sa2_render_mode.cpp`). Both are 720
  now: the game's own 1280x720 in both modes. Docked, the swapchain stays at the TV's size and the picture is scaled
  up. An `alice.toml` on the SD can still set it back.
- **Shadows:** UE3's `[SystemSettings]` in Xe-AliceEngine.ini (Coalesced_INT.bin) has `DynamicShadows = True` and
  `LightEnvironmentShadows = True`. `sub_8242F4B0` loads one SystemSettings section into an FSystemSettingsData
  (r3). It first builds (name, field) pairs on its stack: L"DynamicShadows" (820C5F54, stored at sp+384 by
  8242F530) with r31+808 (sp+388, 8242F55C), and L"LightEnvironmentShadows" (820C5F74, sp+392) with r31+812
  (sp+396). It has 5 callers (82430CBC, 82430E18, 82430ED0, 8243175C, 82432964; sections L"SystemSettings" 820C3C2C
  and L"SystemSettingsEditor" 820C3C00). `app/src/alice_settings.cpp` overrides it: after the original, +808 and
  +812 are 0 unless `alice_shadows = true`. The disc files are unchanged.
- **PC check, Renut/Vulkan, the same input script, shots at 130/160/190 s (the orphanage corridor):** 8 loads
  logged at boot (6 with both values at 1, now 0; 2 already 0). With shadows on: 32,792 draws/s, GPU 5.3 ms a frame,
  render thread 4.9 ms. Off: 30,595 draws/s (−6.7 %), GPU 4.6 ms (−14 %), render thread 5.0 ms. 30.00 fps in both
  (the PC is not the limit). The pictures differ only by Alice's shadow on the floor and its contact darkening.
  Not yet on the console.
- **The frame rate cap:** Xe-AliceEngine.ini `[Engine.Engine]` has `bSmoothFrameRate = TRUE`,
  `MinSmoothedFrameRate = 22`, `MaxSmoothedFrameRate = 31` (and `[Engine.GameEngine] MaxSmoothedFrameRate = 58`;
  `UseVsync = True`). So the game targets 30. 60 would need the smoothing cap raised and the present interval
  halved, and the game logic checked at a different delta time. The console doesn't hold 30 in heavy scenes yet (GPU
  45-52 ms after the rooftop load).

### Fourth console run: shadows off, 720p (2026-11-03, 18:20-18:27)

Log: out/nxlink.log (the third run's is kept as out/nxlink_run3.log).
- The 8 settings loads at boot, as on the PC: DynamicShadows / LightEnvironmentShadows 1 -> 0 in 6 of them.
- **The user: "the rooftop works great"**: no white-out. So the white-out came from the shadow passes, not from
  the eye adaptation alone.
- fps per 10 s: orphanage and streets 27-30 (GPU 16-34 ms); after a load (18:24:30), 16-23 fps with the GPU at
  36-47 ms. The user asked about the water: the heavy windows are likely where the camera faces the water.
- Clocks: the hold thread raised the CPU 71 times and the GPU 105 times in 7 minutes. The loop checked the CPU
  before re-applying the handheld configuration (apmSetPerformanceConfiguration), which puts the CPU back to 1020,
  so the CPU could sit at 1020 MHz for up to a second each time (windows of 25-27 fps with the GPU at 16-25 ms).
  Fixed: the CPU check now comes after the configuration and the GPU (alice_handheld_clocks.cpp).

### More SystemSettings switches (2026-11-03)

The whole (name, field) table `sub_8242F4B0` builds, found by following its register values to the stack stores
(name at sp+N, r31+offset at sp+N+4): StaticDecals +0x0C, DynamicDecals +0x10, UnbatchedDecals +0x14,
DynamicLights +0x1C, CompositeDynamicLights +0x20, SHSecondaryLighting +0x24, DirectionalLightmaps +0x28,
MotionBlur +0x2C, DynamicTonemapping +0x30, MotionBlurPause +0x34, DepthOfField +0x38, AmbientOcclusion +0x3C,
Bloom +0x40, UseHighQualityBloom +0x44, Distortion +0x48, FilteredDistortion +0x4C, DropParticleDistortion +0x50,
LensFlares +0x54, FogVolumes +0x58, FloatingPointRenderTargets +0x5C, OneFrameThreadLag +0x60, AllowD3D10 +0x6C,
AllowRadialBlur +0x70, SpeedTreeLeaves +0x04, SpeedTreeFronds +0x08, OnlyStreamInTextures +0x2FC, UseVsync +0x30C,
UpscaleScreenPercentage +0x314, Fullscreen +0x320, DynamicShadows +0x328 and LightEnvironmentShadows +0x32C (as
found by hand before), bEnableBranchingPCFShadows +0x34C ... bAllowWholeSceneDominantShadows +0x360,
bAllowFracturedDamage +0x390.

New keys, each true (the game's own value) by default, false = forced off after every load: `alice_distortion`
(Distortion, FilteredDistortion, DropParticleDistortion: the refraction pass that water uses), `alice_depth_of_field`,
`alice_bloom` (UseHighQualityBloom only), `alice_lens_flares`, `alice_fog_volumes`. PC: all of them read 1 before
they were zeroed, as the ini says (True). Water reflections are scene captures (USceneCaptureReflectComponent), which
have no SystemSettings switch: not covered yet.

### The 30 fps cap, and 60 (2026-11-03)

- The cap is the present interval: Alice asks for **D3DPRESENT_INTERVAL_TWO** (device +13872 = 2; PaceSwap now logs
  `presentation interval 0x2: 2 refreshes a frame`). Renut paces each Swap by it (sa2_renut_pacing.cpp).
- With `--sa2_renut_vblank_pacing=false` (PC, gameplay): 57-58 fps. The game's own limit is UE3's frame smoothing,
  `[Engine.GameEngine] MaxSmoothedFrameRate = 58` (it overrides `[Engine.Engine]`'s 31).
- `alice_frame_rate = 60` (default 30): one refresh a frame. PC, the same input script: 57.1-57.7 fps, GPU 4.2-6.2 ms;
  the screenshot at 190 s shows Alice at the same place as at 30 fps, so game speed follows time, not frames. At 58
  fps against a 60 Hz display, about one frame in 30 is shown for two refreshes. Not yet run on the console, which
  doesn't hold 30 in heavy scenes.
- Stock clocks for a test: `--alice_cpu_mhz=0 --alice_handheld_gpu_mhz=0 --sa2_gpu_boost=false`.

### Fifth console run: stock clocks (2026-11-03, 18:46-18:48)

`--alice_cpu_mhz=0 --alice_handheld_gpu_mhz=0 --sa2_gpu_boost=false`, handheld, shadows off, 30 fps cap. Log:
out/nxlink_stock.log. No `[clocks]` line: nothing touched. (The try before it, 18:42, ended with Atmosphere
crashing at the intro movie, out/nxlink_crash1.log; the second try with the same options got past it, so not
reproduced.)
- Movies and menu 29.5 fps (GPU 2.5 ms); the first 3D scene 29.5 (GPU 12-31 ms).
- Gameplay: 8.6-18.7 fps, GPU 48-101 ms a frame; the last minute 16.8 fps at GPU 59 ms, render thread ~8 ms. So at
  stock it is GPU-bound throughout, about 2-3x the GPU time of the held 768 MHz runs.

### The optimised codegen, stage A (2026-11-03)

Why: mk9-nx (UE3 2011, the same sa2-nx SDK) measured its fights 11 -> 47-54 fps on the Switch with this stage alone;
its console profile showed the main thread waiting a quarter of its samples on the classic code's global lock
(mtmsrd r13 -> REX_ENTER_GLOBAL_LOCK) against UE3's worker threads. Alice ran the classic code until now.
- `app/perf_overrides.toml` (stage A: cr/ctr/xer/reservation as locals, skip_msr, dform_disp_split, fctiwz_inline,
  fp_moves_modeless), `app/codegen_flavor.toml` (included by alice_manifest.toml), `tools/codegen.sh --flavor`,
  `tools/post_codegen.py` (pch_no_volatile, loop_barriers, direct_calls from sa2-nx; appended to the build's own
  generator command in app/CMakeLists.txt). The flavour's name goes into the first `[enh]` log line.
- Codegen 356 s: 16 pch macros without volatile; 34,734 loop headers, 25,188 with a barrier; 182,811 direct calls,
  456 hooked addresses respected (every BANJO_RENUT_HOOK* and alice_settings.cpp's sub_8242F4B0).
- PC (Renut/Vulkan, the same input script): 30.00 fps, the same screens at 130/160/190 s as the classic build (mean
  pixel difference 0.1-1.5 of 255: animation timing). The classic tree is kept in out/generated_classic, its NRO in
  out/alice_classic.nro.
- Not yet: stage B (non_volatile_as_local + elide_lr_stores; needs tools/read_before_write.py on the code generated
  with it: mk9-nx's first build without that crashed at boot), ro_constants / float_loads / cold traps, LTO.
- Other ports' tips noted for later: kernel_critsec_spin = 1024 (mk9-nx +1 %, a run-time key), the network log's
  sends as a cause of long frames (mk9-nx: test hitches without log_network), MadnessPatch's
  bUseBackgroundLevelStreaming = 0 (an [Engine.Engine] config property: needs a config-lookup hook like
  masseffect-nx's ini override), its high-fps fixes (movement, camera, PhysX, cloth/hair: the 60 fps key needs them).

### The optimised codegen on the console: a glitched picture, bisecting (2026-11-03 evening)

- Sixth console run (out/alice_optimised_a.nro, stage A + the three post steps; log out/nxlink_opt_glitch.log):
  runs a bit faster (gameplay 21-30 fps, GPU 20-45 ms), but **the user: Alice's body and every texture glitched**
  (her eyes and hair fine). The PC build of the same tree (clang, x86) was right (shots at 130/160/190 s).
- Seventh run (out/alice_opt_volatile.nro: the same with `-DREX_GUEST_VOLATILE=volatile`, CMake option
  ALICE_GUEST_VOLATILE): **the same glitch**. So not the no-volatile pch.
- Ruled out by reading: the direct calls (the Switch ELF has 25 strong hooks, sub_X at another address than
  __imp__sub_X; none of them is called directly by the generated code); the physical-window offset of the D-form
  macros (0 on the Switch); strict aliasing (-fno-strict-aliasing is on the generated code); the lwsync/sync
  translation (atomic fences, both flavours); the pch diff (the classic pch already had dform_disp_split; stage A adds
  only REX_CONFIG_{CR,CTR,XER,RESERVED}_AS_LOCAL and SKIP_MSR). skip_msr by reading: 617 lock sections in the classic
  code, all single lwarx/stwcx. (or ldarx/stdcx.) updates except sub_82FF8410 (InterlockedPushEntrySList: its one
  plain store is the new entry's own link, before the 64-bit CAS); the optimised form of it is right. Not set:
  -fwrapv (neither does sa2-nx).
- Eighth build (in progress): the classic code with skip_msr alone (codegen_flavor.toml: `skip_msr = true` and
  `# alice_post_steps = false`, which tools/post_codegen.py reads: no pch rewrite, no barriers, no direct calls).
  Right picture -> skip_msr stays (mk9-nx's big gain), and the cr/ctr/xer/reserved locals and the post steps are
  tested next one at a time; glitched -> skip_msr is the cause.

### skip_msr alone is right on the console; 480p and the draw-count switches (2026-11-03 night)

- Eighth console run (out/alice_skipmsr.nro, log out/nxlink_skipmsr.log): **the user: "looks good now"**. So
  skip_msr is innocent; the glitch is in the cr/ctr/xer/reserved locals or the post steps (direct calls, barriers),
  still to split. 22 gameplay windows: 25.8 fps on average, 16 under 27; heavy windows GPU-bound (31-43 ms).
- Ninth run, the same NRO with `--alice_screen_percentage=66.7` (854x480 scene; log out/nxlink_480p.log): the user
  "it improved well"; the GPU fell to ~21 ms in the heavy windows. The slow windows left are CPU-bound by the draw
  count: 17.4 fps at ~2,060 draws a frame (36,000 a second), the game thread 57 ms Swap to Swap, the render thread
  18.5 ms a frame, the GPU 25 ms.
- Tenth run, plus `--alice_particle_lod_bias=1 --alice_distortion=false`: 20-30 fps; the slow windows have the most
  draws (~1,650 a frame at 20 fps against ~750 at 30), the GPU 21-28 ms.
- New switches (alice_settings.cpp, a float and an int table besides the UBOOLs): alice_decals (StaticDecals +0x0C,
  DynamicDecals +0x10, UnbatchedDecals +0x14), alice_decal_distance (DecalCullDistanceScale +0x18),
  alice_foliage_distance (FoliageDrawRadiusMultiplier +0x308), alice_skeletal_lod_bias (SkeletalMeshLODBias +0x64).

### skip_msr + the register locals: right, and faster (2026-11-04)

- Eleventh console run (out/alice_locals.nro: skip_msr, cr/ctr/xer/reserved_as_local, no post steps; settings
  480p, particle LOD 1, distortion off, foliage 0.5, kernel_critsec_spin 1024; log out/nxlink_locals.log): **the
  user: "it looks good, it improved a bit more"**. 54 gameplay windows: 28.0 fps on average (18 under 27); windows
  over 1,500 draws a frame: 23.6 fps (the same settings with skip_msr alone: 24.7 on average, heavy 20.5).
- So the console glitch of the full stage A is in the post steps. The volatile build (seventh run) still had the
  barriers and the direct calls: the direct calls are the suspect (tools/direct_calls.py; GCC then inlines guest
  functions into each other). Next: no-volatile + barriers without direct calls.
- Profile at the "sunbeams" (`--renut_gpu_profile=10 --banjo_renut_diag_gpu_shaders=true`, out/nxlink_profile_beams.log):
  36.9 ms a frame there, 24.2 ms away from them. The beams' blended draws cost under 0.41 ms each; the difference
  is four opaque scene shaders (PS 26BBB63CB0FBB5B6, 9799A2B6AB81293A, EB1C336D82835754, 49F6C0D33CBE55F1: 15.4 ms at
  58/153/137/63 draws a frame against 6.9 ms at 27/71/65/27): the forest in that view, ~2,200 draws a frame, 16-17 fps.
- User report: with the Shrink sense, glitches on the walls with the hidden purple drawings. To check: distortion
  back on (the sense effect may draw through it).
- Atmosphere crashed twice right after a send, before the intro movie (18:42 stock-clock run; 23:0x run without
  log_network); the next send each time ran. The SD log (logs/ next to the NRO) not read yet.

### Depth bias: Renut never applied it (2026-11-04)

- The user, with the Shrink sense: the hidden purple drawings on the walls z-fight, also with distortion back on
  (twelfth console run, 720p: 26.6 fps on average over 20 windows, the GPU over 33 ms in 9; the user chose 480p).
- Cause: nothing in Renut sets a depth bias (no setDepthBias call, no depthBias in any pipeline desc), so the game's
  DepthBias / SlopeScaleDepthBias (decals, overlays) was dropped and every decal drew at its wall's depth.
- Fix: MakeKey (draw.cpp) takes PA_SU_POLY_OFFSET_FRONT/BACK_SCALE/_OFFSET from device +0x2A50-0x2A5C (m_PointPacket)
  when PA_SU_SC_MODE_CNTL bit 11 or 12 enables them, into PipelineKey::poly_offset_scale / _offset; Build
  (pipeline.cpp) sets desc.depthBias = offset x 2^24 (D3D9's depth units to steps of a 24-bit target, as Xenia's
  unorm24 factor) and slopeScaledDepthBias = scale / 16 (the native SetRenderState stores it x16). Chain reuse now
  also checks bytes 0x2A50-0x2A5F (it compared only 10112-10599, so a decal right after its wall would have kept
  the wall's key). Key: alice_depth_bias (default true). The pipeline list file starts over (its key size changed).
- PC (Renut/Vulkan, the input script): one bias seen in the orphanage: `mode control 00019802, slope scale -0,
  offset 6e-05` (both enables set); 30.00 fps; the shots at 130/160/190 s the same scenes as before. Not yet on the
  console, where the drawings are.
- Defaults on the Switch now (BuiltInConfig): alice_screen_percentage 66.7, alice_particle_lod_bias 1,
  alice_foliage_distance 0.5, kernel_critsec_spin 1024 (the user's choice after the runs above).

### Console runs 13-16: spikes, the square under Alice, the read cache (2026-11-04 night)

All on out/alice_depthbias.nro (skip_msr + locals, depth bias), handheld, CPU 1785 / GPU 768.
- 13 (defaults: 480p, particle LOD 1, foliage 0.5, critsec spin; log out/nxlink_depthbias.log): **z-fighting fixed**
  (the user). 28.6 fps on average; 12 of 28 windows have a frame over 100 ms, worst 2.37 s. The spikes are the
  shader variants compiled at first use ("uam: run-time variant", 49 compiles, 115 ms on average; the 2.37 s one is a
  28 KB pixel-shader variant at 01:05:25.6). The oil on the floor shows only near Alice.
- 14 (+ banjo_gpu_output_trim / blend_skip / bool_spec off, particle LOD back to 0; out/nxlink_nospec.log): 29.1
  fps; 162 compiles (the generic variants were not in the SD cache yet); worst 4.35 s. The oil still only near Alice;
  **a square on the ground under Alice**, first seen with the depth-bias build.
- 15 (+ alice_decals false; out/nxlink_nodecals.log): **the square is gone** (a decal drawn wrong once it is in front
  of its surface: to fix on the PC). 29.3 fps over 44 windows; 73 compiles, DKSH cache 235 hits. Spikes left: with
  compiles in the window (0.4-1.65 s) and without any, with slow SD reads (1.0 s at 01:23:13 and 01:27:03): the game
  loading an effect's data at first use, again minutes later (the user: snail shells, getting hurt, the first shots,
  entering new zones).
- 16 (+ `sa2_io_ranges_min_kb=4 sa2_io_ranges_mb=256`, the SDK's exact-range read cache down to 4 KB reads;
  out/nxlink_iocache.log): 39 % hits (1,548, 54.9 MB from RAM), worst spike 0.87 s, but 14 of 35 windows still over
  100 ms and 27.5 fps; **Alice's body invisible, only her hair**. Dropped. The cached path triggers the same physical
  heap callbacks (xfile.cpp ReadSync) as a read from the SD; suspect: a file the game rewrites and reads back (a
  cached range served stale). Not checked yet.
- Switch defaults now (out/alice_best.nro): 480p, foliage 0.5, critsec spin 1024, decals off, the three Renut
  specialisations off; particle LOD bias dropped.

### No shader compiles while playing: every variant compiled on the PC (2026-11-04 night)

What the other ports did (the user's reading list): mk9-nx's async pipelines (`mk9_async_pipelines`: draws left out
while a worker builds the pipeline) were turned **off in its 1.0.1** (coloured triangles and long waits on the
console); what removed its compile hitches was a DKSH cache built at build time from the console's pipeline list (0
compiles on a fresh console). masseffect-nx ships a prewarm list the same way. A list only covers places already
played, though, and the spikes left here are in places the console has not seen.
- So the variants were made predictable instead. With banjo_gpu_bool_spec / blend_skip / output_trim off (the
  defaults since run 14) and now banjo_deko3d_vs_outputs off (constants 905 and 906 depended on the vertex/pixel
  shader pairing), Build() (render/pipeline.cpp) and plume's createGraphicsPipeline give a vertex shader only 904 = 1
  (not tessellated; banjo_deko3d_tess_spec) and a pixel shader only 909 = 1 (no depth/stencil writes;
  banjo_deko3d_early_z); 907, 908, 910-912 only in non-default modes or for banjo-nx's listed shaders.
- `tools/renut/precompile_all_variants.py`: every shader of out/deko3d_shaders/glsl_opt in its variants {} / {904}
  and {} / {909} (a constant its GLSL does not declare makes no define), the text and key as
  tools/renut/deko3d_variant_cache.py (copied from sa2-nx; accepts the 200-byte keys of the depth-bias change): 29,701
  shaders, 54,179 variants (28,337 pixel shaders declare 909, 195 vertex shaders 904).
- Check of the text: the console's log (out/nxlink_best.log) names 25 run-time pixel variants with 909 = 1 alone; each
  has a pixel shader of exactly its source size minus the 39-byte define line.
- LoadCache (banjo_renut_deko3d.cpp) now indexes the records from 8 MB chunks (one pass) instead of a seek and three
  reads a record: 54,179 SD round trips otherwise. It logs the time.

### Stage B without LTO: still glitched (2026-11-04 evening)

- Console run (out/alice_stageB.nro: stage B + all post steps + -fwrapv, ALICE_SWITCH_LTO=OFF; log
  out/nxlink_stageB_nolto.log): CPU 1785 / GPU 768, the DKSH cache 54,179 records in 3,037 ms, 0 compiles, 30.00 fps
  with the GPU at ~10 ms a frame in the first gameplay windows. **The user: Alice's whole body still has glitched
  textures.** So LTO is innocent, and -fwrapv does not fix the glitch.
- What is known: stage A without post steps right (run 11); stage A + the three post steps glitched, also volatile
  (runs 6-7); stage B + post steps glitched (with and without LTO).
- Next, both at once: out/alice_final_direct.nro (stage A + direct calls only + -fwrapv, built 2026-11-04 05:04,
  never on the console) on the console, and a stage B build without direct calls
  (`# alice_post_steps = no_direct_calls`, a new mode of tools/post_codegen.py: no-volatile pch + loop barriers only;
  out/alice_stageB_nodirect.nro).
- Console run (out/alice_stageB_nodirect.nro: stage B + no-volatile pch + loop barriers, no direct calls, -fwrapv, no
  LTO; log out/nxlink_stageB_nodirect.log; the user's screenshot out/console_shots/stageB_nodirect_menu.jpg, the main
  menu): **Alice's skin and dress a confetti of wrong texels, eyes and hair right**. So not the direct calls (alone).
- Every glitched build so far has the loop barriers, the one right optimised build (run 11) has no post steps; the
  no-volatile pch is ruled out by run 7 (volatile, still glitched). Suspect: tools/loop_barriers.py's narrow barrier,
  `__asm__ __volatile__("" : "+m"(*(uint8_t (*)[0x100001000ull])base))`, under the Switch's GCC 16 (the PC's clang
  build is right).
- Next build (in progress): stage B with `# alice_post_steps = false` (out/alice_stageB_nopost.nro). Right -> the
  barriers (or the pch with them) are the cause and stage B's own options stay; then try -DREX_LOOP_BARRIER_FULL.
  Glitched -> non_volatile_as_local / elide_lr_stores.
- Console run (out/alice_stageB_nopost.nro: stage B, `# alice_post_steps = false`, -fwrapv, no LTO; log
  out/nxlink_stageB_nopost.log): **the user: the same glitch**. So not the post steps either.
- The same NRO with `--alice_radial_blur=true --alice_depth_of_field=true` (log out/nxlink_stageB_nopost_blur.log;
  the game logs `AllowRadialBlur 1`): **the same**. Not the new blur defaults.
- Since alice_lite.nro (right) every build has had stage B's non_volatile_as_local + elide_lr_stores and -fwrapv.
  Next build: the same code with ALICE_GENERATED_WRAPV=OFF (out/alice_stageB_nopost_nowrapv.nro).
- Console run (out/alice_stageB_nopost_nowrapv.nro: the same code, ALICE_GENERATED_WRAPV=OFF; log
  out/nxlink_stageB_nowrapv.log): **the user: the same**. So -fwrapv is innocent: **stage B's own options
  (non_volatile_as_local + elide_lr_stores) glitch Alice on the console**, with or without post steps, LTO or -fwrapv.
  The PC (clang) is right with them. Not split further yet. A candidate from sa2-nx's notes (enhancements.md,
  "non_volatile_as_local + elide_lr_stores"): after a longjmp the setjmp caller's r14-r31 locals keep the failing
  call's values (Alice's guest setjmp 82DBA170 / longjmp 82DBA440, the call sites 82CEAA78 ... 82CEB3C8). Also not
  done here and done in sa2-nx before keeping them: the verify mode and the pixel tests on the PC.
- Decision: the final build goes back to the stage A flavour (out/codegen_flavor_stageA_good.toml: skip_msr +
  cr/ctr/xer/reserved locals, no post steps), no -fwrapv, no LTO, with today's settings (no motion/radial blur, no DoF,
  CompositeDynamicLights on): out/alice_release.nro. Stage B's flavour file is kept as out/codegen_flavor_stageB.toml.
- Console run (out/alice_release.nro, log out/nxlink_release.log): **the user: "fixed!!!"**, Alice right. The
  DKSH cache 54,179 records in 3,067 ms. This is the final build.
- The user on the final build (2026-11-05 ~01:20): **the sky normal** (so the green sky was not radial blur / DoF
  off). Two problems:
  - with the Shrink sense (L) some signs on the walls are missing: decals, off since run 15 (alice_decals false, for
    the square under Alice). To fix: that square on the PC, then decals back on.
  - in one part **Alice's body missing, only her head and arms drawn**. Not located yet. The log
    (out/nxlink_release.log) has the first bindless-table pressure of any run: 01:14:19.376 "bindless table nearly
    full; 5244 idle host textures released (6145 of 8192 slots in use)" and 01:14:19.381 "three quarters full ...
    325 cold host textures released", during the load of Chapter1_W1_VoT_04 (EvictIdleTexturesLocked /
    EvictColdTexturesLocked, textures.cpp). Link to the missing body not shown; compare run 16 (stale reads, body
    invisible).
- PC check (2026-11-05 01:22, out/pc/alice = stage B PC build, Renut/Vulkan, console settings, the console's
  checkpoint save copied to ~/.local/share/alice/...; the PC's own save backed up in out/sd_backup/pc_save_20261105_011846,
  the console's in out/sd_backup/console_save_20261105_011846): Continue loads Vale of Tears with **Alice's whole body
  drawn** (shot at 100 s), no bindless-table warning. The user: the body went missing **after obtaining the knife**.
  Next: Continue from that checkpoint on the console with the log (missing at once -> tied to the place; only after a
  while -> the texture table pressure).

### Clean-up before publishing (2026-11-05)

- Removed (in git history; sa2-nx keeps the tools): the optimised flavour's post-codegen rewrites and stage B audit
  (tools/direct_calls.py, pch_no_volatile.py, loop_barriers.py, find_self_loops.py, read_before_write.py,
  app/perf_overrides.toml, codegen.sh --flavor), the bisect CMake options (ALICE_GUEST_VOLATILE,
  ALICE_GENERATED_WRAPV, ALICE_SWITCH_LTO), the stage B share_registers mark; the one-time Renut retargeting scripts
  (tools/renut/retarget.py, retarget_alice.py: applied; the tables are in docs/d3d-census.md); three Renut sources no
  build compiled (d3d/hooks/state.cpp, guest/photo_capture.cpp, guest/widescreen.cpp: Nuts & Bolts game code);
  tools/renut/known_shaders.txt (Monster High's 1,699 shader hashes: 0 of them are Alice's).
- tools/post_codegen.py only records the flavour's name now ("optimised: skip_msr, ...").
- Fixed: tools/build_pc.sh and build_switch.sh default to ALICE_RENUT=ON (OFF built an NRO with no renderer, and
  tools/build_from_disc.sh never set it); build_from_disc.sh follows Alice's shader pipeline (extract_shaders.sh,
  switch_shaders.sh, precompile_all_variants.py) instead of Monster High's play-to-capture; package_switch.sh puts
  deko3d_shaders.bin next to the NRO; THIRD_PARTY_NOTICES.md names this game; file headers and 2026-10 tags renamed
  from mhnwis-nx by the bootstrap say Alice / mhnwis-nx again.
- **Start-up 25 s faster:** asset_pack / asset_pack_build off on the Switch. The SDK tried to pack game_root at every
  start and gave up (4,535 MB, over FAT32's 4 GB: out/nxlink_release.log 00:59:41.646 -> 01:00:06.612, nothing else
  running).
- Decals on by default again (the user: the Shrink sense's signs are decals); the square near Alice is the oil decal.
- The decals-on run (2026-11-05 02:0x) also hit the bindless table at three quarters (02:18:19, 5,970 cold textures
  released); the user: Alice's body fine throughout. So the table pressure alone does not hide her body.
