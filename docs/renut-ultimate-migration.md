# Renut NX Ultimate / ReXGlue migration

Alice now builds against the ReXGlue SDK and Renut renderer stack vendored from the supplied `renut_nx_ultimate_base` source tree. A separate `sa2-nx` checkout is no longer needed by the build.

## Imported implementation

- `sdk/`: the complete newer ReXGlue SDK, including its Switch platform layer, runtime, code generator and vendored SDK dependencies.
- `app/src/renut_engine/gpu/`: the current Renut GPU implementation, matching the supplied Renut NX Ultimate tree. The only source-level difference in this GPU directory is Alice's `banjo_renut_select.cpp`, which maps Alice's `sa2_renderer` setting to Renut or the Xenos reference renderer.
- Shader ABI: `gpu.cmake` uses the matching current `shader_common.h` from `app/thirdparty/reblue-XenosRecomp/XenosRecomp`. An older Alice-era copy was unused (the imported `gpu.cmake` overwrote its path); that dead copy and misleading override have been removed so the current renderer and shader translator share one ABI definition.
- `app/thirdparty/plume/`: current Plume renderer and deko3d backend.
- `app/thirdparty/reblue-XenosRecomp/`: current Xenos shader translator and its bundled dependencies.
- `app/thirdparty/uam/`: the current bundled UAM compiler.
- `tools/renut/deko3d_*.py`: updated from Renut NX Ultimate, including the newer GLSL conversion, optimisation passes, shader package format and variant cache. Linux executable paths are used by the Linux build.
- `tools/renut/extract_shaders.sh` and `ue3_extract_shaders.cpp` remain Alice-specific: they extract the shader containers from Alice's cooked UE3/LZX packages. Runtime shader capture remains a fallback for shaders not found by the package scan.

## Switch build configuration

The Alice CMake project now applies Renut Ultimate's Switch build defaults before including the generated ReXGlue CMake integration:

- SDK libraries are emitted into each Switch build directory (`REXGLUE_OUTPUT_IN_BUILD=ON`) so they participate in that build's LTO/PGO settings.
- GCC's early register allocation and outlined atomics are disabled by default for the Switch build (`BANJO_SWITCH_EARLY_RA=OFF`, `BANJO_SWITCH_OUTLINE_ATOMICS=OFF`).
- Small SDK helpers are forced inline (`SASRT_FORCE_INLINE_HELPERS=ON`).
- VMX estimate/fused forms and single-precision fused scalar operations use the Renut Ultimate defaults (`SASRT_VMX_FAST_ESTIMATES=ON`, `SASRT_VMX_FUSED_MADD=ON`, `BLUR_FMADDS_SINGLE=ON`). These are not bit-identical to the exact forms in every floating-point edge case.
- Alice's Switch build defaults to exact per-region FPCR behavior (`BLUR_FPCR_ONE_MODE=OFF`) until Alice's own CG-13 census shows no denormal-sensitive gameplay. The GitHub Actions `fpcr_one_mode` input can opt into the faster path for an A/B; it flushes scalar denormals and is not bit-exact.
- Near-exact transformations remain OFF by default (`BLUR_NEAR_EXACT=OFF`) pending game-specific census and validation.
- Store-card writes use the view-only optimisation (`BLUR_CARD_VIEWS_ONLY=ON`).
- `app/codegen_flavor.toml` now enables Renut Ultimate's shared codegen transformations: D-form split, inline integer conversions/division, prefetch hints, rotate/shift forms, modeless FP compares/moves, FP-mode lookahead and FP copy forwarding. Alice-specific register-diet rewrites (`non_volatile_as_local`, `elide_lr_stores`, `non_argument_as_local`) remain disabled because Alice's existing console notes record rendering corruption with related transformations.

For a fully conservative floating-point comparison build, configure the Switch build with `-DSASRT_VMX_FAST_ESTIMATES=OFF -DSASRT_VMX_FUSED_MADD=OFF -DBLUR_FMADDS_SINGLE=OFF -DBLUR_FPCR_ONE_MODE=OFF`. These switches affect generated guest code and the SDK runtime, so regenerate code and rebuild when changing them. PC builds compile the CG-13 counters into `alice_recomp`; build the PC reference executable with `tools/build_pc.sh`, run `out/pc/alice` with `--sa2_diag_runtime_census=true` during representative gameplay, and inspect the `[census] CG-13` and `[census] denormal sites` lines (the `tools/census_sites.py` helper resolves the reported offsets) before opting into one-mode.

## Build and test

On Linux, install clang 20 or newer, CMake 3.25 or newer, Ninja, Python 3, Git, the X11/XCB/Wayland development packages and devkitPro's devkitA64/libnx/deko3d/switch-tools. Then build from your own extracted Alice disc:

```sh
tools/build_from_disc.sh /path/to/your/extracted/Alice-disc --jobs 2
```

The output is `out/nx/sdcard/switch/alice-nx/`; copy the resulting `out/nx/sdcard/switch/` folder to the SD card. The build creates the ReXGlue host code generator, extracts and translates Alice's shaders, compiles the deko3d shader variants, builds the NRO and packages the SD-card folder.

The GitHub Actions workflow is `.github/workflows/build.yml`. It builds the same in-tree SDK and renderer stack and uploads the NRO plus shader cache as a short-retention artifact. Keep the repository and artifacts private: they contain translated code and shaders from the user's own game copy.

## Validation status

The migration's source-level checks cover shell syntax, Python syntax, workflow YAML syntax, imported component file parity and Linux tool-path consistency. A complete NRO build and on-console test still require the user's Alice disc files, clang 20+ and devkitPro toolchain; those inputs are not part of the source archives.

## Compatibility and optimization audit (2026-11-17)

- The Renut GPU directory is byte-for-byte aligned with the supplied Renut NX Ultimate source except for Alice's renderer selector. The active shader ABI is the current XenosRecomp `shader_common.h`, not the old Alice-era duplicate.
- The UE3 package extractor is intentionally retained: Alice stores most material shaders in cooked `SeekFreeShaderCache` data, and its prior scan found 29,701 distinct shader containers; runtime capture covered additional shaders as a fallback. Replacing this with the base's generic XEX/bundle dump would not be equivalent.
- Alice's renderer selector and `alice_renut_port.cpp` are integration glue, not old renderer internals. They provide the `sa2_renderer` choice and globals expected by the imported Renut hooks.
- The previously tested Alice codegen stage-A choices remain: `skip_msr`, CR/CTR/XER/reservation locals. The more aggressive `non_volatile_as_local` and `elide_lr_stores` stage-B combination is not enabled because Alice's recorded Switch tests showed corrupted character textures with it.
- Renut Ultimate's shared codegen and Switch compiler options are integrated. The non-exact floating-point options (`SASRT_VMX_FAST_ESTIMATES`, `SASRT_VMX_FUSED_MADD`, `BLUR_FMADDS_SINGLE`) still require Alice-specific image validation. `BLUR_FPCR_ONE_MODE` is now OFF by default for Alice until the PC CG-13 census is clean; GitHub Actions exposes an explicit opt-in for A/B testing. These are measured optimization candidates, not a claim of pixel-identical output on Alice.
- No new performance or visual-fidelity claim is made until an Alice build is run and compared in the same scene. The next validation sequence is: verify the full shader set and cache, compare Renut output against the Xenos reference on PC/Ryujinx, then measure same-session A/Bs on the Switch.
