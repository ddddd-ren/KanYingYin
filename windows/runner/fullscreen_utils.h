// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef FULLSCREEN_UTILS_H_
#define FULLSCREEN_UTILS_H_

#include <cstdint>
#include <functional>

#include <Windows.h>

class FullscreenUtils {
 public:
  using Completion = std::function<void()>;

  static void EnterNativeFullscreen(HWND window, Completion completion = {});

  static void ExitNativeFullscreen(HWND window, Completion completion = {});

 private:
  static constexpr auto kFlutterViewWindowClassName = L"FLUTTERVIEW";
  static constexpr UINT_PTR kTransitionTimerId = 0x4B59;
  static constexpr UINT kTransitionDurationMs = 180;

  static void StartTransition(HWND window, const RECT& start, const RECT& end,
                              Completion completion);
  static void FinishTransition();
  static void CALLBACK TransitionTimerProc(HWND window, UINT message,
                                           UINT_PTR timer_id, DWORD tick);
  static LONG Interpolate(LONG start, LONG end, double progress);

  static bool fullscreen_;
  static RECT rect_before_fullscreen_;
  static bool transition_active_;
  static RECT transition_start_;
  static RECT transition_end_;
  static ULONGLONG transition_started_at_;
  static HWND transition_window_;
  static Completion transition_completion_;
};

#endif  // FULLSCREEN_UTILS_H_
