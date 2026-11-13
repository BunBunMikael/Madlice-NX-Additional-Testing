# Alice: Madness Returns - ReXGlue recompiled project (the SDK's init template).
#
# SDK boilerplate lives in generated/rexglue.cmake (written by the code generator). Configure with
# -DREXSDK_DIR=<sa2-nx>/sdk; tools/host_shaders.sh (the PC tree, for the shader tools) and tools/build_switch.sh do it.

cmake_minimum_required(VERSION 3.25)
project(alice LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# alice-nx (2026-11-03, as sa2-nx): the build re-runs the generator by itself whenever an input in codegen.d changes,
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
# sa2-nx's does: there the SDK's plugin loader calls the plugin's entry points directly (no dynamic libraries), so the
# link needs one. It is never started there: Renut draws on deko3d, and without a Vulkan driver it could not run.
rexglue_setup_target(alice GPU_PLUGINS xenos)

# The SDK builds its perf counters (and perf_log_csv) only into builds other than Release (its own directory scope).
target_compile_definitions(alice PRIVATE $<$<NOT:$<CONFIG:Release>>:ALICE_PERF_CSV=1>)

# As sa2-nx: the SDK compiles itself with these, but they do not reach the generated game code built here. Without
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
