# Alice: Madness Returns - ReXGlue recompiled project (the SDK's init template).
#
# SDK boilerplate lives in generated/rexglue.cmake (written by the code generator). Configure with
# -DREXSDK_DIR=<this repository>/sdk; tools/host_shaders.sh (the PC tree, for the shader tools) and tools/build_switch.sh do it.

cmake_minimum_required(VERSION 3.25)
project(alice LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(BANJO_SWITCH_EARLY_RA "Leave GCC's AArch64 early register allocation pass on (Switch; miscompiles, see above)" OFF)
# Line tables (-g1) for the three hot renderer files, so tools/switch_hot_lines.py can say where inside a function a
# console profile's samples fall. -g does not change the generated code: an ELF built with this ON has every function
# at the address of the same sources built with it OFF, so it names the samples of a run of the normal NRO.
option(BANJO_SWITCH_RENDERER_LINES "Switch: line tables for the hot native renderer files (profiling aid)" OFF)
if(REXGLUE_PLATFORM_SWITCH AND NOT BANJO_SWITCH_EARLY_RA)
    add_compile_options(-mearly-ra=none)
    add_link_options(-mearly-ra=none)
endif()
# banjo-nx (package 27, codegen round): atomics inline. GCC's default for AArch64 calls out-of-line helpers
# (__aarch64_cas4_acq, __aarch64_ldadd8_rel, ...) that test for LSE atomics at run time; the A57 has none, so every
# atomic was a call, a load and a branch before the same load-exclusive / store-exclusive loop this writes inline (75
# call sites in the ELF of package 26: shared_ptr counts, the SDK's and the renderers' atomics). The same instructions.
option(BANJO_SWITCH_OUTLINE_ATOMICS "Switch: GCC's out-of-line atomic helpers (its default; OFF writes them inline)" OFF)
if(REXGLUE_PLATFORM_SWITCH AND NOT BANJO_SWITCH_OUTLINE_ATOMICS)
    add_compile_options(-mno-outline-atomics)
endif()

# renut-ultimate (2026-11-07): the SDK's libraries in each Switch build folder (sdk/CMakeLists.txt), so they can be built
# with each folder's LTO and PGO options (BANJO_SWITCH_SDK_OPT below).
if(REXGLUE_PLATFORM_SWITCH)
    set(REXGLUE_OUTPUT_IN_BUILD ON CACHE BOOL "The SDK's libraries and tools in this build folder")
endif()
# sasrt-nx (2026-11-11, port 71): the SDK's small helpers forced inline (sdk/include/rex/ppc/diet_ops.h,
# REX_SMALL_HELPER). Before the SDK's targets (generated/rexglue.cmake adds them), so the switch reaches them too.
option(SASRT_FORCE_INLINE_HELPERS "The SDK's one-instruction helpers forced inline (OFF: REX_NO_FORCED_HELPERS)" ON)
if(NOT SASRT_FORCE_INLINE_HELPERS)
    add_compile_definitions(REX_NO_FORCED_HELPERS)
endif()
# sasrt-nx (2026-11-11, port 72; its idea 43 F1-F4): VMX's estimates and multiply-add / -subtract in their faster AArch64
# forms (tools/vmx_float_macros.py): vrsqrtefp / vrefp as frsqrte / frecpe with two Newton steps, vlogefp as a NEON log2
# estimate, vmaddfp / vnmsubfp as one fused multiply-add. NOT bit-identical to the exact forms the port computed before:
# sasrt-nx's console fuzz (64 M lanes each) put the estimates within 3 ulp (vrsqrtefp) and 1 ulp (vrefp) of exact and the
# fused forms different in 2.4 % of lanes (one rounding, as the 360's own vmaddfp); the 360's estimates are good to about
# 1/4096. ON at the user's word (2026-11-11). AArch64 only: the PC keeps the exact expressions. Global, so the SDK and
# the copies see the same. An existing build folder keeps a cached OFF: cmake -DSASRT_VMX_FAST_ESTIMATES=ON
# -DSASRT_VMX_FUSED_MADD=ON on it.
option(SASRT_VMX_FAST_ESTIMATES "VMX vrsqrtefp / vrefp / vlogefp as AArch64 estimates (not bit-exact)" ON)
option(SASRT_VMX_FUSED_MADD "VMX vmaddfp / vnmsubfp as one fused multiply-add (not bit-exact)" ON)
if(SASRT_VMX_FAST_ESTIMATES)
    add_compile_definitions(REX_VMX_FAST_ESTIMATES)
endif()
if(SASRT_VMX_FUSED_MADD)
    add_compile_definitions(REX_VMX_FUSED_MADD)
endif()
# blur-nx (2026-11-12, the user: "Please do the fmadds change"): the scalar fmadds / fmsubs / fnmadds / fnmsubs rounded once
# in single precision, as the Xenon does (tools/fma_single.py, sdk/include/rex/ppc/fma_single.h), instead of the double
# fused multiply-add rounded again to single: one unit in the last place apart in rare cases (about one operation in a
# few hundred million), and single-precision chains stay in float registers. OFF: the double rounding, as before.
option(BLUR_FMADDS_SINGLE "Scalar fmadds and kin rounded once in single precision (the Xenon's rounding; not bit-exact to the double form)" ON)
if(NOT BLUR_FMADDS_SINGLE)
    add_compile_definitions(REX_FMADDS_DOUBLE_ROUNDING)
endif()
# blur-nx (2026-11-12, codegen-ideas-3 CG-13; the user: "build CG 13 ... it probably should be off by default"): all guest
# float code with the host's flush mode on (rex/ppc/context.h, rex/ppc/diet_ops.h): no `msr fpcr` switch in the game code
# after a thread's first, and the any-mode float helpers as the plain operations. NOT bit-exact: the Xenon's scalar FPU
# keeps denormals (values below FLT_MIN / DBL_MIN), which this flushes to zero as its VMX unit does. The PC census
# (sa2_diag_runtime_census: "[census] CG-13" lines, tools/census_sites.py --denormal) counts the results it changes.
# A compile-time switch: every generated file, the copies and the SDK runtime change with it (retrain the PGO profile).
# renut-ultimate (2026-11-13, port 133; the user: "turn it on by default in the base ... because it's universal big CPU
# benefit"): ON by default in the Switch build (each switch is an `msr fpcr` on the console: Katamari's game code does
# about 1.2 million a second on the PC; blur-nx's console +4.6 % fps). OFF by default in the PC build, which stays
# exact: the census counts what the Switch build changes only where the mode still switches
# (tools/cg13_census.ps1). An existing build folder keeps its cached value: -DBLUR_FPCR_ONE_MODE=ON / OFF changes it.
# Alice has not yet had a CG-13 denormal census in representative gameplay. Keep the exact scalar mode by default;
# the GitHub Actions input ALICE_FPCR_ONE_MODE can opt into the faster one-mode path for a measured A/B.
set(_blur_fpcr_one_mode_default OFF)
option(BLUR_FPCR_ONE_MODE "All guest float code in the flush mode (no FPCR switches; not bit-exact for scalar denormals)"
       ${_blur_fpcr_one_mode_default})
if(BLUR_FPCR_ONE_MODE)
    add_compile_definitions(REX_FPCR_ONE_MODE)
endif()
# renut-ultimate (2026-11-14, port 140; blur-nx's docs/cpu-near-exact-50-1113.md): the compile-time near-exact switches
# (rex/ppc/diet_ops.h, context.h, tools/near_exact.py), each the code before when off. NOT bit-exact in rare cases:
# #1 REX_NX_SNAN_PASS, #2 REX_NX_FCTI_NO_NAN, #17 REX_NX_DIV_NO_CHECK, #41 REX_NX_FCMP_NO_UN, #42 REX_NX_VMINMAX_FAST,
# #5 REX_NX_XER_SO_ZERO, #19 REX_NX_NO_TRAPS (a trap only logs). OFF in the base: each game runs the PC census
# (banjo_diag_runtime_census, the "[census] near-exact" lines) before turning them on. blur-nx's census took #2 (NaN
# conversions not rare: 80 a second) and #42 (4 % of vector max/min lanes differ) out of the set; BLUR_NX_ONLY names
# switches to use alone (a ;-list, for a bisect; #2 and #42 only this way), BLUR_NX_SKIP leaves some out. Every
# generated file, the copies and the SDK change with them: retrain the PGO profile.
option(BLUR_NEAR_EXACT "blur-nx's near-exact compile-time switches (not bit-exact in rare cases)" OFF)
set(BLUR_NX_ONLY "" CACHE STRING "With BLUR_NEAR_EXACT: only these switches (a ;-list, for a bisect; empty: all)")
set(BLUR_NX_SKIP "" CACHE STRING "With BLUR_NEAR_EXACT: every switch but these (a ;-list)")
set(_blur_nx_switches REX_NX_SNAN_PASS REX_NX_DIV_NO_CHECK REX_NX_FCMP_NO_UN REX_NX_XER_SO_ZERO REX_NX_NO_TRAPS)
if(BLUR_NEAR_EXACT AND NOT BLUR_NX_ONLY STREQUAL "")
    list(APPEND _blur_nx_switches REX_NX_FCTI_NO_NAN REX_NX_VMINMAX_FAST)
endif()
if(BLUR_NEAR_EXACT)
    foreach(_s ${_blur_nx_switches})
        if((BLUR_NX_ONLY STREQUAL "" OR _s IN_LIST BLUR_NX_ONLY) AND NOT _s IN_LIST BLUR_NX_SKIP)
            add_compile_definitions(${_s})
            message(STATUS "near-exact: ${_s}")
        endif()
    endforeach()
endif()
# renut-ultimate (2026-11-14, port 140; blur-nx's #66, exact): the generated tree's store cards by the copies' rule
# (tools/store_cards.py: only the pages whose cards Renut reads, a card written only when not set yet). ON, as in
# blur-nx's every build; OFF: every store marks its card as before.
option(BLUR_CARD_VIEWS_ONLY "The generated tree's store cards only for Renut's views, written only when set (exact)" ON)
if(BLUR_CARD_VIEWS_ONLY)
    add_compile_definitions(REX_CARD_VIEWS_ONLY)
endif()
include(generated/rexglue.cmake)

# alice-nx: the build re-runs the in-tree ReXGlue generator whenever an input in codegen.d changes,
# which rewrites app/generated; tools/post_codegen.py (the flavour's name for the log) is appended to the same command.
# The Switch cross build has no generator target.
if(TARGET alice_codegen)
    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    add_custom_command(OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/codegen.build.stamp" APPEND
        COMMAND "${CMAKE_COMMAND}" -E env "REXSDK_DIR=${REXSDK_DIR}"
                "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../tools/post_codegen.py")
endif()
# The flavour's name in the first "[enh]" log line (tools/post_codegen.py writes the file).
set(ALICE_FLAVOR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/generated/codegen_flavor.txt")
if(EXISTS "${ALICE_FLAVOR_FILE}")
    file(READ "${ALICE_FLAVOR_FILE}" ALICE_FLAVOR)
    string(STRIP "${ALICE_FLAVOR}" ALICE_FLAVOR)
    add_compile_definitions("SA2_BUILD_FLAVOR=\"${ALICE_FLAVOR}\"")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${ALICE_FLAVOR_FILE}")
endif()

set(ALICE_SOURCES
    src/main.cpp
    src/alice_screenshot.cpp
    src/alice_shm.cpp
    src/alice_settings.cpp
)

# Diagnostic sources added for one build only, e.g. the Direct3D census (tools/d3d/census_build.py). Empty normally.
set(ALICE_EXTRA_SOURCES "" CACHE STRING "Extra source files (diagnostic builds only)")
list(APPEND ALICE_SOURCES ${ALICE_EXTRA_SOURCES})

if(WIN32)
    add_executable(alice WIN32 ${ALICE_SOURCES})
else()
    add_executable(alice ${ALICE_SOURCES})
endif()

# The emulated Xenos GPU (loaded by gpu_plugin = "xenos", src/alice_app.h). The Switch build links it too, as
# The SDK's plugin loader calls the plugin's entry points directly (no dynamic libraries), so the
# link needs one. It is never started there: Renut draws on deko3d, and without a Vulkan driver it could not run.
rexglue_setup_target(alice GPU_PLUGINS xenos)

# PC-only CG-13 census: count scalar denormal/underflow cases in the translated game code. This lets Alice decide
# whether the Switch-only one-flush-mode optimisation is safe for its own gameplay, rather than inheriting another
# game's result. The Switch binary never carries the census instrumentation.
if(NOT REXGLUE_PLATFORM_SWITCH AND TARGET alice_recomp)
    target_compile_definitions(alice_recomp PRIVATE REX_DIET_CENSUS_ON)
endif()

# The SDK builds its perf counters (and perf_log_csv) only into builds other than Release (its own directory scope).
target_compile_definitions(alice PRIVATE $<$<NOT:$<CONFIG:Release>>:ALICE_PERF_CSV=1>)

# The SDK compiles itself with these, but they do not reach the generated game code built here. Without
# -ffp-contract=off the compiler fuses the guest's separate multiplies and adds into FMAs (GCC does by default, clang
# within a statement), and results drift from the Xbox 360's; strict aliasing is unsafe for recompiled code.
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    foreach(_alice_target alice alice_recomp)
        if(TARGET ${_alice_target})
            target_compile_options(${_alice_target} PRIVATE -ffp-contract=off -fno-strict-aliasing)
        endif()
    endforeach()
endif()
# alice_register.cpp is one function of ~57,000 SetFunction calls, run once at start-up. GCC's optimiser spends about
# 50 minutes on it (the longest job of the Switch build, by far); unoptimised it compiles in seconds and the start-up
# cost is nothing next to loading the game.
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/generated/default/alice_register.cpp"
                            PROPERTIES COMPILE_OPTIONS "-O0" SKIP_PRECOMPILE_HEADERS ON)
if(REXGLUE_PLATFORM_SWITCH)
    # Where the NRO is on the SD card when no loader passes its path (an emulator): its folder holds the settings,
    # the logs, the shader caches and the game files.
    if(TARGET rexcore)
        target_compile_definitions(rexcore PRIVATE REX_SWITCH_FALLBACK_EXE="/switch/alice-nx/alice.nro")
    endif()
    # The homebrew menu's entry. Its icon is made at build time from your own disc's dashboard art (tools/disc_icon.py,
    # run by tools/build_switch.sh, into out/: game art, never committed); without it, app/switch/icon.jpg (original
    # artwork, tools/make_icon.py).
    set(ALICE_NRO_ICON "${CMAKE_CURRENT_SOURCE_DIR}/../out/nx_icon.jpg")
    if(NOT EXISTS "${ALICE_NRO_ICON}")
        set(ALICE_NRO_ICON "${CMAKE_CURRENT_SOURCE_DIR}/switch/icon.jpg")
    endif()
    rexglue_switch_add_nro(alice
        NAME "Alice: Madness Returns"
        AUTHOR "alice-nx (unofficial)"
        VERSION "1.0.0"
        ICON "${ALICE_NRO_ICON}")
endif()

# Renut's Direct3D-level renderer (the route to the Switch: docs/d3d-census.md), chosen at boot with
# sa2_renderer = "renut"; the emulated GPU stays the default and the reference.
option(ALICE_RENUT_RENDERER "Link Renut's Direct3D-level renderer (sa2_renderer = renut)" ON)
if(ALICE_RENUT_RENDERER)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/alice_renut_gpu.cmake")
endif()
