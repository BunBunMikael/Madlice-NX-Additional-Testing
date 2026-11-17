# Alice: Renut's Direct3D-level renderer, selected at boot with sa2_renderer = "renut"
# (src/renut_engine/gpu/banjo_renut_select.h). The renderer implementation and gpu.cmake are imported from
# Renut NX Ultimate; this file supplies Alice's game-specific shader inputs and Switch build integration.
# looks for them: thirdparty/plume (plume at Renut's version), thirdparty/reblue-XenosRecomp (its translator, DXC, zstd,
# smol-v, xxHash), thirdparty/imgui, cmake/collect_captured_shaders.cmake.
#
# An OBJECT library, not a static one: its hooks replace the generated code's weak sub_X definitions, and a static
# archive's members are only pulled in for undefined symbols, so the hooks would silently not be linked.

# The shader containers its shader cache is built from: Renut's own dump of default.xex and the bundles
# (tools/dump_shaders.py of a Renut checkout; banjo-nx's harvest has wrapped containers Renut's XenosRecomp does not
# take). A normal variable, so it shadows gpu.cmake's cache entry.
set(RENUT_SHADER_DUMP_DIR "${CMAKE_SOURCE_DIR}/../out/renut_shader_dump")
set(RENUT_ASSETS_DIR "${CMAKE_SOURCE_DIR}/../assets/game_root" CACHE PATH "Alice game assets")

# Renut's XenosRecomp is built as an ExternalProject (gpu.cmake): it gets this build's whole host toolchain, not only
# the compiler paths (tools/renut_gpu_import.py adds the variable to gpu.cmake). On the PC, clang for the MSVC ABI.
set(BANJO_RENUT_XENOS_RECOMP_ARGS "")
foreach(_banjo_var CMAKE_C_COMPILER_TARGET CMAKE_CXX_COMPILER_TARGET CMAKE_LINKER_TYPE CMAKE_C_FLAGS CMAKE_CXX_FLAGS
                   CMAKE_AR CMAKE_RC_COMPILER CMAKE_MT)
    if(DEFINED ${_banjo_var} AND NOT "${${_banjo_var}}" STREQUAL "")
        list(APPEND BANJO_RENUT_XENOS_RECOMP_ARGS "-D${_banjo_var}=${${_banjo_var}}")
    endif()
endforeach()

# Renut's SDK exports o1heap as rex::o1heap; banjo-nx's SDK fork names it o1heap.
if(TARGET o1heap AND NOT TARGET rex::o1heap)
    add_library(rex::o1heap ALIAS o1heap)
endif()

# The Switch build is a cross build on a Windows host: Renut's XenosRecomp (a host tool) cannot be built with the
# console's compiler. Its shader cache comes from a PC build of the same tree (tools/renut_switch_shader_cache.py
# writes a copy without the DXIL arrays, which only Windows reads).
if(REXGLUE_PLATFORM_SWITCH)
    # plume's Switch backend (UnleashedRecomp-NX's patches, thirdparty/plume): VK_NN_vi_surface on libnx's window and
    # Mesa's static NVK, the same driver the SDK links (REXGLUE_SWITCH_NVK_SDK).
    set(PLUME_PLATFORM_SWITCH ON CACHE BOOL "" FORCE)
    set(PLUME_SWITCH_DEVKITPRO "${DEVKITPRO}" CACHE PATH "" FORCE)
    set(PLUME_SWITCH_NVK_ROOT "${REXGLUE_SWITCH_NVK_SDK}" CACHE PATH "" FORCE)
    set(PLUME_SWITCH_NVK_LIBRARY "${REXGLUE_SWITCH_NVK_SDK}/lib/libvulkan.a" CACHE FILEPATH "" FORCE)
    # banjo-nx (2026-10-20): no Vulkan driver in the Switch build unless REXGLUE_SWITCH_NVK (sdk/cmake/rexglue_switch.cmake).
    set(PLUME_SWITCH_NVK_LINK "${REXGLUE_SWITCH_NVK}" CACHE BOOL "" FORCE)
    # banjo-nx (2026-10-17): plume's deko3d back end (renut_gpu_backend = "deko3d", docs/deko3d-renderer.md) and the
    # uam it compiles shader variants with on the console.
    set(PLUME_SWITCH_UAM_DIR "${CMAKE_SOURCE_DIR}/thirdparty/uam" CACHE PATH "" FORCE)
    set(PLUME_DEKO3D ON CACHE BOOL "deko3d back end (Switch)" FORCE)
    # The host shaders' deko3d blobs (gpu.cmake renut_host_shader) need the PC tools tools/deko3d_build_tools.sh builds.
    set(BANJO_DEKO3D_HOST_SHADERS ON)
    set(BANJO_DEKO3D_SPIRV_CROSS "${CMAKE_SOURCE_DIR}/../out/deko3d_tools/spirv-cross-build/spirv-cross" CACHE FILEPATH
        "SPIRV-Cross for the deko3d host shaders (tools/deko3d_build_tools.sh)")
    set(BANJO_DEKO3D_UAM "${CMAKE_SOURCE_DIR}/../out/deko3d_tools/uam-build/uam" CACHE FILEPATH
        "uam (thirdparty/uam built for the PC) for the deko3d host shaders (tools/deko3d_build_tools.sh)")
    foreach(_banjo_tool BANJO_DEKO3D_SPIRV_CROSS BANJO_DEKO3D_UAM)
        if(NOT EXISTS "${${_banjo_tool}}")
            message(FATAL_ERROR "No ${${_banjo_tool}}: run tools/deko3d_build_tools.sh first")
        endif()
    endforeach()
    # katamari-nx (2026-11-02, futari-nx's design): the release build (tools/renut_release_shaders.py,
    # app/out/renut_switch_release): no translated game shader in the NRO and the shader table without SPIR-V; the game's
    # shaders come from deko3d_glsl.bin beside the NRO, which the web installer makes from the player's files. OFF (the
    # everyday build): every translated shader built in (app/out/renut_switch).
    option(BANJO_RENUT_RELEASE_SHADERS "Switch: no translated game shader in the NRO (deko3d_glsl.bin beside it)" OFF)
    if(BANJO_RENUT_RELEASE_SHADERS)
        set(_banjo_renut_shaders "${CMAKE_SOURCE_DIR}/out/renut_switch_release")
    else()
        set(_banjo_renut_shaders "${CMAKE_SOURCE_DIR}/out/renut_switch")
    endif()
    # The game shaders' GLSL for deko3d (tools/deko3d_shader_package.py), embedded next to the SPIR-V cache.
    set(BANJO_DEKO3D_GLSL_CPP "${_banjo_renut_shaders}/deko3d_glsl_switch.cpp" CACHE FILEPATH
        "The deko3d GLSL package's source (tools/deko3d_shader_package.py)" FORCE)
    set(BANJO_RENUT_SHADER_CACHE_CPP "${_banjo_renut_shaders}/shader_cache_switch.cpp" CACHE FILEPATH
        "Renut's shader cache for the Switch build (from a PC build: tools/renut_switch_shader_cache.py)" FORCE)
    function(banjo_renut_shader_cache_override TARGET)
        if(NOT EXISTS "${BANJO_RENUT_SHADER_CACHE_CPP}")
            message(FATAL_ERROR "No ${BANJO_RENUT_SHADER_CACHE_CPP}: build the PC tree first, then run "
                                "tools/renut_switch_shader_cache.py (Renut's XenosRecomp runs on the host)")
        endif()
        target_sources(${TARGET} PRIVATE "${BANJO_RENUT_SHADER_CACHE_CPP}")
        set_source_files_properties("${BANJO_RENUT_SHADER_CACHE_CPP}" PROPERTIES SKIP_PRECOMPILE_HEADERS ON)
    endfunction()
endif()

set(RENUT_TOOLS_DIR "${CMAKE_SOURCE_DIR}/../tools")
# gpu.cmake deliberately selects the matching shader_common.h from the imported XenosRecomp revision.
include("${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/gpu.cmake")

add_library(alice_renut_gpu OBJECT
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_select.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_tuning.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/ultimate.cpp"  # renut-ultimate: the ported fixes' switches
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/sasrt_gpu_round.cpp"  # sasrt-nx's GPU rounds (2026-11-08, night)
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_checks.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_record.cpp"
    # banjo-nx (2026-10-19, latency batch 3): the display's refresh for the frame limiter (it reads the presents' fences)
    "${CMAKE_SOURCE_DIR}/src/renut_engine/display_sync.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/perf/frame_stats.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/alice_renut_port.cpp"
    "${CMAKE_SOURCE_DIR}/src/cpu/sa2_enhancements.cpp"
    "${CMAKE_SOURCE_DIR}/src/cpu/alice_enhancements_port.cpp"
    "${CMAKE_SOURCE_DIR}/src/cpu/sa2_gpu_boost.cpp"
    "${CMAKE_SOURCE_DIR}/src/cpu/alice_handheld_clocks.cpp"
    "${CMAKE_SOURCE_DIR}/src/me/sa2_render_mode.cpp")
target_include_directories(alice_renut_gpu PRIVATE
    "${CMAKE_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/src"
    "${REXGLUE_ENTRYPOINT_INCLUDE_DIR}"
    # banjo_renut_tuning.cpp: the Switch thread helpers (threading_switch.h, through src/me/me_platform_compat.h).
    "${REXSDK_DIR}/src/core")
target_link_libraries(alice_renut_gpu PRIVATE rex::runtime)
if(REXGLUE_PLATFORM_SWITCH)
    # banjo-nx (2026-10-17): the deko3d back end's glue and the game shaders' GLSL package (docs/deko3d-renderer.md).
    target_sources(alice_renut_gpu PRIVATE "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_deko3d.cpp")
    if(EXISTS "${BANJO_DEKO3D_GLSL_CPP}")
        target_sources(alice_renut_gpu PRIVATE "${BANJO_DEKO3D_GLSL_CPP}")
        set_source_files_properties("${BANJO_DEKO3D_GLSL_CPP}" PROPERTIES SKIP_PRECOMPILE_HEADERS ON)
    elseif(BANJO_RENUT_RELEASE_SHADERS)
        message(STATUS "banjo: no GLSL package in the NRO (BANJO_RENUT_RELEASE_SHADERS): deko3d_glsl.bin beside it")
    else()
        message(WARNING "No ${BANJO_DEKO3D_GLSL_CPP}: renut_gpu_backend = deko3d will have no game shaders "
                        "(tools/deko3d_shader_package.py)")
    endif()
endif()
if(COMMAND rexglue_apply_target_settings)
    rexglue_apply_target_settings(alice_renut_gpu)
endif()
renut_gpu_setup(alice_renut_gpu)
# banjo-nx (2026-10-23, render-thread round): the draw path's function-local statics (cvars read once: about 15 a draw,
# StoreCards / PhysicalOf at every page check) without the thread-safe guard, whose fast path is a load-acquire (LDARB)
# that holds back every later load on the A57. Sound here: these files run on the render thread; the one other caller
# (the content verifier thread's hashes) reaches only statics that every thread initialises to the same pointer.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set_property(SOURCE
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/render/draw.cpp"
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/guest/command_buffers.cpp"
        TARGET_DIRECTORY alice_renut_gpu APPEND PROPERTY COMPILE_OPTIONS "-fno-threadsafe-statics")
endif()
# banjo-nx (2026-10-28): BANJO_SWITCH_RENDERER_LINES also gives Renut's hot render-thread files line tables (-g1), so a
# console profile's samples name source lines (rt_breakdown.py). night_gpu4's ELF had none for them (every sample ":?").
# Debug info only: the generated code is the same.
if(REXGLUE_PLATFORM_SWITCH AND BANJO_SWITCH_RENDERER_LINES)
    set_property(SOURCE
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/render/draw.cpp"
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/render/textures.cpp"
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/render/surfaces.cpp"
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/guest/command_buffers.cpp"
        TARGET_DIRECTORY alice_renut_gpu APPEND PROPERTY COMPILE_OPTIONS "-g1")
endif()
# banjo-nx (2026-10-20): a Switch build without the Vulkan driver (REXGLUE_SWITCH_NVK OFF) always boots Renut on
# deko3d, the one renderer that does not need it (banjo_renut_select.cpp, backend.cpp ResolveBackend).
if(REXGLUE_PLATFORM_SWITCH AND NOT REXGLUE_SWITCH_NVK)
    target_compile_definitions(alice_renut_gpu PRIVATE BANJO_SWITCH_NO_VULKAN=1)
endif()
target_link_libraries(alice PRIVATE alice_renut_gpu)
target_compile_definitions(alice PRIVATE BANJO_RENUT_RENDERER=1 SA2_RENUT_RENDERER=1)
