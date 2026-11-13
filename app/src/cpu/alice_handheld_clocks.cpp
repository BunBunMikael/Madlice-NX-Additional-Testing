// Alice: the handheld clocks (alice_handheld_gpu_mhz, alice_handheld_emc_1600).
//
// The first console runs with sa2_gpu_boost (GPU 460.8 MHz, memory 1331.2) were GPU-bound: 21-27 ms of GPU work a
// frame in gameplay, 38-47 fps (log of 2026-10-20 21:28; the scene's shadow pass, resolves and three scene shaders,
// already early-Z and alpha-specialised). The docked clocks (GPU 768, memory 1600) are 1.67x the GPU, the user's call
// (2026-10-21, "make the nro with those profiles") instead of sys-clk.
//
// How, after switch_apm.cpp's lessons (sa2-nx sdk/src/ui): pcv reimposes the memory clock of the active apm
// configuration, so the memory comes from the configuration itself (0x92220007: GPU 460.8 + EMC 1600, an official
// handheld one), and the GPU is raised above it with clkrst, as sys-clk does, checked again every second (a mode change
// or waking from sleep applies the configuration's clocks again). Docked: nothing is touched. At the end the
// configuration the console had is requested again, which puts its clocks back.
// WHY IT IS EXACT: clocks, not settings: the same frames are drawn, sooner.
// RISK: more power draw and heat in handheld mode (the docked clocks, not above them).
#include "cpu/alice_handheld_clocks.h"

#include <atomic>
#include <thread>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/platform.h>

#include "cpu/sa2_enhancements.h"

#if REX_PLATFORM_SWITCH
#include <switch.h>
#endif

// alice-nx (2026-11-05): the user's call: stock clocks by default (0), the overclock is the player's own choice.
REXCVAR_DEFINE_INT32(alice_handheld_gpu_mhz, 0, "ALICE",
                     "Handheld GPU clock in MHz: 0 = not touched, the console's stock clocks (default). 1-460: "
                     "sa2_gpu_boost's official 460.8 MHz profile, nothing held. 461-768: held by the game while it "
                     "runs (768 = the docked clock). Read at start")
    .range(0, 768)
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
// alice-nx (2026-11-02): the CPU. Gears of War 2's port (UE3 too, gears2-nx README "Performance") ran 12-17 fps at
// the stock CPU clock and 24-27 at 1785 MHz: Unreal's game thread is the limit. Alice's first console runs with Renut
// held the GPU at 768 but left the CPU at its stock 1020 MHz: 15-18 fps in gameplay, with the GPU at 21-25 ms and the
// render thread at 9-12 ms of a 59 ms frame, so the game's own threads were the limit (docs/alice-notes.md). The
// user's call (2026-11-02): hold 1785 MHz. Docked and handheld alike (both modes' CPU is 1020); the rate the CPU had
// at start comes back at exit.
// RISK: an overclock above Nintendo's clocks (sys-clk's usual 1785): more heat and power draw.
// alice-nx (2026-11-05): default 0 (stock 1020 MHz); the player opts in.
REXCVAR_DEFINE_INT32(alice_cpu_mhz, 0, "ALICE",
                     "CPU clock in MHz, held by the game while it runs, docked and handheld: 0 = not touched, the "
                     "console's stock 1020 (default). 1224, 1428, 1581 or 1785: an overclock (more heat and power "
                     "draw). Read at start")
    .range(0, 1785)
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_BOOL(alice_handheld_emc_1600, true, "ALICE",
                    "With alice_handheld_gpu_mhz above 460: the memory at 1600 MHz in handheld mode (the docked "
                    "clock; configuration 0x92220007) instead of 1331.2 (0x92220008). Read at start")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

namespace alice::clocks {

#if REX_PLATFORM_SWITCH
namespace {

constexpr u32 kConfigEmc1600 = 0x92220007u;  // GPU 460.8, EMC 1600
constexpr u32 kConfigEmc1331 = 0x92220008u;  // GPU 460.8, EMC 1331.2
constexpr u32 kMarginHz = 20000000u;
constexpr int kReportEverySeconds = 60;

std::atomic<bool> g_stop{false};
std::thread g_thread;
u32 g_config_original = 0;
bool g_has_original = false;
u32 g_cpu_original_hz = 0;  // alice-nx: the CPU's rate at start, put back at exit

bool ClockOf(PcvModuleId module, u32 &hz) {
  hz = 0;
  ClkrstSession session{};
  if (R_FAILED(clkrstOpenSession(&session, module, 3))) return false;
  const bool ok = R_SUCCEEDED(clkrstGetClockRate(&session, &hz));
  clkrstCloseSession(&session);
  return ok;
}

bool SetClock(PcvModuleId module, u32 hz) {
  ClkrstSession session{};
  if (R_FAILED(clkrstOpenSession(&session, module, 3))) return false;
  const bool ok = R_SUCCEEDED(clkrstSetClockRate(&session, hz));
  clkrstCloseSession(&session);
  return ok;
}

void Hold(u32 gpu_hz, u32 config, u32 cpu_hz) {
  bool handheld_before = false;
  bool told = false, cpu_told = false;
  int raises = 0, raises_reported = 0, failures = 0, cpu_raises = 0, cpu_failures = 0;
  for (int second = 0; !g_stop.load(std::memory_order_relaxed); ++second) {
    ApmPerformanceMode mode = ApmPerformanceMode_Invalid;
    const bool handheld = R_SUCCEEDED(apmGetPerformanceMode(&mode)) && mode == ApmPerformanceMode_Normal;
    if (handheld != handheld_before) {
      REXLOG_INFO("[clocks] {}", handheld ? "handheld: holding the clocks" : "docked: the console's own clocks");
      handheld_before = handheld;
      told = false;
    }
    if (handheld && gpu_hz) {
      u32 current = 0;
      if (R_SUCCEEDED(apmGetPerformanceConfiguration(ApmPerformanceMode_Normal, &current)) && current != config &&
          R_FAILED(apmSetPerformanceConfiguration(ApmPerformanceMode_Normal, config)) && failures++ == 0) {
        REXLOG_WARN("[clocks] configuration 0x{:08X} refused (was 0x{:08X})", config, current);
      }
      u32 gpu = 0, emc = 0;
      if (ClockOf(PcvModuleId_GPU, gpu) && gpu + kMarginHz < gpu_hz) {
        if (SetClock(PcvModuleId_GPU, gpu_hz)) {
          ++raises;
        } else if (failures++ == 0) {
          REXLOG_WARN("[clocks] clkrst refused the GPU clock {:.1f} MHz (it is at {:.1f})", gpu_hz / 1e6, gpu / 1e6);
        }
      } else if (!told && gpu && ClockOf(PcvModuleId_EMC, emc)) {
        REXLOG_INFO("[clocks] handheld: GPU {:.1f} MHz, memory {:.1f} MHz", gpu / 1e6, emc / 1e6);
        told = true;
      }
    }
    // alice-nx: the CPU, in both modes (a mode change or waking from sleep puts the configuration's clock back).
    // alice-nx (2026-11-03): after the configuration step above, not before it. Re-applying the handheld
    // configuration (apmSetPerformanceConfiguration) also puts the CPU back to the configuration's 1020 MHz, so a
    // CPU check made before it left the CPU at 1020 for up to a second each time (fourth console run: 70 CPU
    // raises and 105 GPU raises in 3.5 minutes).
    if (cpu_hz) {
      u32 cpu = 0;
      if (ClockOf(PcvModuleId_CpuBus, cpu) && cpu + kMarginHz < cpu_hz) {
        if (SetClock(PcvModuleId_CpuBus, cpu_hz)) {
          ++cpu_raises;
          cpu_told = false;
        } else if (cpu_failures++ == 0) {
          REXLOG_WARN("[clocks] clkrst refused the CPU clock {:.1f} MHz (it is at {:.1f})", cpu_hz / 1e6, cpu / 1e6);
        }
      } else if (!cpu_told && cpu) {
        REXLOG_INFO("[clocks] CPU {:.1f} MHz ({} raises so far)", cpu / 1e6, cpu_raises);
        cpu_told = true;
      }
    }
    if (second % kReportEverySeconds == kReportEverySeconds - 1 && raises != raises_reported) {
      REXLOG_INFO("[clocks] the GPU was put back to {:.1f} MHz {} times in all", gpu_hz / 1e6, raises);
      raises_reported = raises;
    }
    for (int i = 0; i < 10 && !g_stop.load(std::memory_order_relaxed); ++i) svcSleepThread(100000000ULL);
  }
}

}  // namespace
#endif

void Start() {
  const int32_t mhz = REXCVAR_GET(alice_handheld_gpu_mhz);
  const int32_t cpu_mhz = REXCVAR_GET(alice_cpu_mhz);
  if (mhz <= 0 && cpu_mhz <= 0) {
    REXLOG_INFO("[clocks] stock clocks: nothing touched (alice_cpu_mhz / alice_handheld_gpu_mhz in alice.toml)");
    return;
  }
  if (mhz <= 460 && cpu_mhz <= 0) {
    sa2::enh::ApplyGpuBoost();
    return;
  }
#if REX_PLATFORM_SWITCH
  if (R_FAILED(clkrstInitialize())) {
    REXLOG_WARN("[clocks] no clkrst");
    if (mhz > 0) sa2::enh::ApplyGpuBoost();  // its 460.8 MHz profile instead
    return;
  }
  if (cpu_mhz > 0 && ClockOf(PcvModuleId_CpuBus, g_cpu_original_hz))
    REXLOG_INFO("[clocks] CPU {} MHz held (it was {:.1f})", cpu_mhz, g_cpu_original_hz / 1e6);
  if (mhz > 0 && mhz <= 460) {
    // The GPU as sa2_gpu_boost has it; the thread holds the CPU alone (gpu_hz 0: the handheld part does nothing
    // above the configuration).
    sa2::enh::ApplyGpuBoost();
  }
  g_has_original = R_SUCCEEDED(apmGetPerformanceConfiguration(ApmPerformanceMode_Normal, &g_config_original));
  const u32 config = REXCVAR_GET(alice_handheld_emc_1600) ? kConfigEmc1600 : kConfigEmc1331;
  if (mhz > 460)
    REXLOG_INFO("[clocks] handheld: GPU {} MHz over configuration 0x{:08X} (the console's: 0x{:08X})", mhz, config,
                g_has_original ? g_config_original : 0u);
  g_thread = std::thread(Hold, mhz > 460 ? u32(mhz) * 1000000u : 0u, config,
                         cpu_mhz > 0 ? u32(cpu_mhz) * 1000000u : 0u);
#endif
}

void Stop() {
#if REX_PLATFORM_SWITCH
  if (!g_thread.joinable()) return;
  g_stop.store(true, std::memory_order_relaxed);
  g_thread.join();
  if (g_has_original) apmSetPerformanceConfiguration(ApmPerformanceMode_Normal, g_config_original);
  if (g_cpu_original_hz) SetClock(PcvModuleId_CpuBus, g_cpu_original_hz);  // alice-nx
  clkrstExit();
  REXLOG_INFO("[clocks] the console's configuration 0x{:08X} again", g_config_original);
#endif
}

}  // namespace alice::clocks
