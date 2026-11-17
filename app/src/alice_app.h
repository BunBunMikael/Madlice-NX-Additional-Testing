// Alice: Madness Returns: the app (rex::ReXApp hooks). Renderer chosen at boot (sa2_renderer): the SDK's
// emulated Xenos GPU ("xenos", the default and the reference) or Renut's Direct3D-level renderer ("renut", the route to
// the Switch: docs/d3d-census.md).

#pragma once

#include <filesystem>
#include <string>
#include <system_error>

#include <rex/cvar.h>
#include <rex/perf/counter.h>

#include <rex/filesystem.h>
#include <rex/input/device_assignment.h>
#include <rex/input/input_system.h>
#include <rex/platform.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/ui/presenter.h>

#include "alice_screenshot.h"
#include "alice_shm.h"

#if SA2_RENUT_RENDERER
#include "cpu/alice_handheld_clocks.h"
#include "cpu/sa2_enhancements.h"
#include "renut_engine/gpu/banjo_renut_capture.h"
#include "renut_engine/gpu/banjo_renut_select.h"
#include "renut_engine/gpu/overlay/app_integration.h"
#endif

#if ALICE_PERF_CSV
REXCVAR_DECLARE(std::string, perf_log_csv);
#endif

class AliceApp : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<AliceApp>(new AliceApp(ctx, "alice", PPCImageConfig));
  }

  // Defaults applied before alice.toml (which may override any of them). The first boot ran without a GPU
  // ("VdInitializeRingBuffer: no GPU emulation loaded (gpu_plugin not set)", 2026-10-20): the emulated Xenos GPU is a
  // plugin, built by GPU_PLUGINS xenos in CMakeLists.txt and loaded by this setting.
  // On the Switch there is no emulated GPU: Renut on deko3d (sa2-nx's sa2_switch_defaults.toml), the game files read
  // from game_root/ next to the NRO, and the log on (logs/ next to the NRO: what a bug report needs). The GPU profile of the console tests is off
  // (renut_gpu_profile = 10.0 and banjo_renut_diag_gpu_shaders = true in alice.toml turn it on again).
  std::string_view BuiltInConfig() const override {
#if REX_PLATFORM_SWITCH
    return "sa2_renderer = \"renut\"\n"
           "renut_gpu_backend = \"deko3d\"\n"
           "sa2_render_height_handheld = 720\n"
           // alice-nx (2026-11-03, the user's request): 720p docked too (the game's own 1280x720, upscaled to the TV).
           "sa2_render_height_docked = 720\n"
           // alice-nx (2026-11-04, the user's choice after the console runs, docs/alice-notes.md): the 3D scene at
           // 480p (the HUD stays 720p), cheaper particle LODs, foliage to half its distance, critical sections spin
           // before they wait (mk9-nx +1 %).
           "alice_screen_percentage = 66.7\n"
           "alice_foliage_distance = 0.5\n"
           "kernel_critsec_spin = 1024\n"
           // alice-nx (2026-11-04, console runs 14-16): decals off until their drawing is fixed (with the depth bias
           // applied, one under Alice shows as a square); the particle LOD bias dropped (it hid the oil on the floors
           // beyond a few metres); Renut's shader specialisations off: one variant per shader instead of several, so
           // fewer compiles while playing (the first-use spikes).
           // alice-nx (2026-11-05, the user): decals back on: the Shrink sense's hidden signs on the walls are decals.
           // The square near Alice (the oil decal, to fix) is the smaller flaw.
           "alice_decals = true\n"
           "alice_motion_blur = false\n"
           // alice-nx (2026-11-04, the user: no blur at all): radial blur and depth of field off.
           "alice_radial_blur = false\n"
           "alice_depth_of_field = false\n"
           "alice_composite_lights = true\n"
           "banjo_gpu_output_trim = false\n"
           "banjo_gpu_blend_skip = false\n"
           "banjo_gpu_bool_spec = false\n"
           // alice-nx (2026-11-04): the vertex shaders' outputs not pruned per pixel shader (constants 905 / 906, which
           // depend on the pairing): with it and the three above, every variant a draw can need is one of
           // {} / {904} (vertex) and {} / {909} (pixel), all compiled on the PC into the SD card's DKSH cache
           // (tools/renut/precompile_all_variants.py): no shader compiles while playing.
           "banjo_deko3d_vs_outputs = false\n"
           // alice-nx (2026-11-05): no asset pack. The game data is 4,535 MB, over FAT32's 4 GB file limit, so the SDK
           // could never build one; trying cost 25 s of black screen at every start (out/nxlink_release.log,
           // 00:59:41.646 -> 01:00:06.612). The files are read from game_root/ next to the NRO.
           "asset_pack = false\n"
           "asset_pack_build = false\n"
           "log_level = \"info\"\n"
           "log_to_file = true\n"
           // The face buttons by letter, as other Switch games: the Switch's A acts as the Xbox A (the SDK's default
           // is by position, its bottom button B as A).
           "input_xbox_layout = false\n";
#else
    return "gpu_plugin = \"xenos\"\n";
#endif
  }

  void OnPostSetup() override {
    // The guest memory is mapped now: its /dev/shm file can go (alice_shm.cpp).
    alice::shm::UnlinkOwnFile();
    // Every controller plays as user 0, the only signed-in user (XamUserGetSigninState reports users 1-3 signed out).
    // With the SDK's default slot policy a second pad was user 1: Start on it at the title screen left the main menu
    // without its panel (background only), most likely waiting on a sign-in for user 1 (player's run, 2026-10-20:
    // Steam Deck controls = pad 0, Xbox Series X controller = pad 1; the same Start from user 0, by input_script, shows
    // the menu). Inferred from those two runs, not traced in the game code.
    if (auto* input = dynamic_cast<rex::input::InputSystem*>(runtime()->input_system())) {
      input->SetDeviceAssignment(std::make_unique<rex::input::SharedAssignment>());
    }
    // The SDK defines perf_log_csv (a per-frame CSV of its perf counters, written at each Flip) but nothing opens the
    // file: open it here. tools/play.sh records with it.
#if ALICE_PERF_CSV
    if (!REXCVAR_GET(perf_log_csv).empty()) {
      rex::perf::SetCsvLogPath(REXCVAR_GET(perf_log_csv));
    }
#endif
    // Test-run screenshots (alice_screenshots, alice_screenshot.cpp), taken from the frame on screen.
#if SA2_RENUT_RENDERER
    if (banjo::renut_gpu::Active()) {
      alice::screenshot::Start([](rex::ui::RawImage& image) { return renut::gpu::CaptureFrame(image); });
      return;
    }
#endif
    alice::screenshot::Start([this](rex::ui::RawImage& image) {
      const auto* rt = runtime();
      const auto* graphics = rt ? rt->graphics_system() : nullptr;
      auto* presenter = graphics ? graphics->presenter() : nullptr;
      return presenter && presenter->CaptureGuestOutput(image);
    });
  }

#if SA2_RENUT_RENDERER
  // Renut's renderer (as sa2-nx's sa2_app.h wires it): no SDK graphics system and no GPU plugin; its own drawer for
  // the SDK's menus, its own swapchain resizing, started once the window exists (the paths are final then).
  // Which of sa2-nx's enhancement switches run (own key and group master), before any guest thread exists, as sa2-nx's
  // OnPostInitLogging does. Without it every SA2_ENHANCEMENT stayed inactive: among them sa2_vsync_relaxed, so on the
  // first console run every frame that missed 1/60 s waited for the next one (274 of 320 frames late a 10 s, 32 fps).
  void OnPostInitLogging() override { sa2::enh::Resolve(); }

  void OnPreSetup(rex::RuntimeConfig& config) override {
    // The clocks (alice_handheld_clocks.cpp): stock by default; the player's alice.toml can raise the CPU and the
    // handheld GPU (at 460.8 MHz, sa2_gpu_boost, the console run of 2026-10-20 was GPU-bound at 38-47 fps).
    alice::clocks::Start();
    if (banjo::renut_gpu::Active()) {
      renut::gpu::ConfigureRuntime(config);
      REXLOG_INFO("graphics: Renut's Direct3D-level renderer (sa2_renderer = renut)");
    }
  }
  std::unique_ptr<rex::ui::ImmediateDrawer> OnCreateImmediateDrawer() override {
    if (banjo::renut_gpu::Active()) return renut::gpu::CreateOverlayDrawer();
    return rex::ReXApp::OnCreateImmediateDrawer();
  }
  void OnWindowPixelSizeChanged(uint32_t pixel_width, uint32_t pixel_height) override {
    rex::ReXApp::OnWindowPixelSizeChanged(pixel_width, pixel_height);
    if (banjo::renut_gpu::Active()) renut::gpu::OnWindowResized();
  }
  std::optional<rex::PathConfig> OnFinalizePaths(const rex::PathConfig& defaults,
                                                 std::function<void(rex::PathConfig)> resume) override {
    if (banjo::renut_gpu::Active()) renut::gpu::StartRenderer(app_context(), [this] { return imgui_drawer(); });
    return rex::ReXApp::OnFinalizePaths(defaults, std::move(resume));
  }
  void OnShutdown() override {
    if (banjo::renut_gpu::Active()) renut::gpu::ShutdownRenderer();
    alice::clocks::Stop();
  }
#endif

  // The game files: assets/game_root (a link to the disc folder) in the executable's folder or any folder above it,
  // unless the config or command line already set game_data_root. The disc names the executable Default.xex; the
  // guest's own lookups are case-insensitive, but this check runs on the host filesystem, so both spellings count.
  void OnConfigurePaths(rex::PathConfig& paths) override {
    // Before the guest memory is created: free what killed or crashed runs left in /dev/shm (alice_shm.cpp).
    alice::shm::RemoveStaleFiles();
    if (!paths.game_data_root.empty()) {
      return;
    }
    std::error_code ec;
    const auto folder = rex::filesystem::GetExecutableFolder();
    for (auto candidate = folder; !candidate.empty(); candidate = candidate.parent_path()) {
      for (const auto& sub : {std::filesystem::path("game_root"), std::filesystem::path("assets") / "game_root"}) {
        const auto root = candidate / sub;
        // Or only its asset pack (the Switch: game_root.nxpack + .nxidx, which the SDK builds from the folder at the
        // first start; the folder may be deleted after that).
        auto pack = root;
        pack += ".nxpack";
        if (std::filesystem::is_regular_file(root / "Default.xex", ec) ||
            std::filesystem::is_regular_file(root / "default.xex", ec) ||
            std::filesystem::is_regular_file(pack, ec)) {
          paths.game_data_root = root;
          return;
        }
      }
      if (candidate == candidate.parent_path()) {
        break;
      }
    }
  }
};
