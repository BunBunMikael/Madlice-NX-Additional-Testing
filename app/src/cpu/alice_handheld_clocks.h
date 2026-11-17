// Alice: the clocks (alice_handheld_clocks.cpp). Default: the console's stock clocks, nothing touched. Opt-in: the CPU
// held (alice_cpu_mhz), the handheld GPU held up to 768 MHz with memory 1600, or sa2_gpu_boost's 460.8 MHz profile
// (alice_handheld_gpu_mhz = 460).
#pragma once

namespace alice::clocks {

void Start();  // once, before the guest starts (OnPreSetup)
void Stop();   // at shutdown: the console's own configuration again

}  // namespace alice::clocks
