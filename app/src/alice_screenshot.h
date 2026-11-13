// Screenshots for test runs (alice_screenshots = "20,40,60"): see alice_screenshot.cpp.

#pragma once

#include <functional>

namespace rex::ui {
struct RawImage;
}

namespace alice::screenshot {

// Starts the screenshot thread when alice_screenshots lists any seconds; returns at once otherwise. grab fills the
// image of the frame on screen and returns false when there is none.
void Start(std::function<bool(rex::ui::RawImage&)> grab);

}  // namespace alice::screenshot
