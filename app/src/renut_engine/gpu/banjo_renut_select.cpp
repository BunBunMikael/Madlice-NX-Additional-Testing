// Alice: select the Direct3D-level Renut renderer or the SDK's Xenos reference renderer.
#include "renut_engine/gpu/banjo_renut_select.h"

#include <string>

#include <rex/cvar.h>
#include <rex/logging/macros.h>

REXCVAR_DEFINE_STRING(sa2_renderer, "renut", "Alice",
                      "Renderer, chosen at boot. renut = Alice's Direct3D-level renderer through plume/deko3d; "
                      "xenos = the SDK's emulated Xbox 360 GPU reference renderer.")
    .allowed({"xenos", "renut"})
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

namespace banjo::renut_gpu {
namespace detail {
int8_t g_active = 0;
bool LatchActive() {
#if BANJO_SWITCH_NO_VULKAN
  static const bool active = [] {
    if (REXCVAR_GET(sa2_renderer) != "renut")
      REXLOG_WARN("sa2_renderer = \"{}\" needs Vulkan, unavailable in this Switch build; using Renut on deko3d",
                  REXCVAR_GET(sa2_renderer));
    return true;
  }();
#else
  static const bool active = [] {
    if (REXCVAR_GET(sa2_renderer) == "xenos") {
      REXLOG_WARN("sa2_renderer = \"xenos\": SDK Xenos reference renderer selected; Renut hooks disabled");
      return false;
    }
    if (REXCVAR_GET(sa2_renderer) != "renut")
      REXLOG_WARN("Unknown sa2_renderer = \"{}\"; using Renut", REXCVAR_GET(sa2_renderer));
    return true;
  }();
#endif
  g_active = active ? 1 : -1;
  return active;
}
}  // namespace detail
}  // namespace banjo::renut_gpu
