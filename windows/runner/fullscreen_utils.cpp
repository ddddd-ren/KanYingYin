// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "fullscreen_utils.h"

#include <algorithm>
#include <cmath>

void FullscreenUtils::EnterNativeFullscreen(HWND window, Completion completion) {
  if (fullscreen_ || transition_active_) {
    if (completion) {
      completion();
    }
    return;
  }
  fullscreen_ = true;

  // The primary idea here is to revolve around |WS_OVERLAPPEDWINDOW| &
  // detect/set fullscreen based on it. In the window procedure, this is
  // separately handled. If there is no |WS_OVERLAPPEDWINDOW| style on the
  // window i.e. in fullscreen, then no area is left for |WM_NCHITTEST|,
  // accordingly client area is also expanded to fill whole monitor using
  // |WM_NCCALCSIZE|.

  auto style = ::GetWindowLongPtr(window, GWL_STYLE);
  if (style & WS_OVERLAPPEDWINDOW) {
    auto monitor = MONITORINFO{};
    auto placement = WINDOWPLACEMENT{};
    monitor.cbSize = sizeof(MONITORINFO);
    placement.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(window, &placement);
    rect_before_fullscreen_ = RECT{
        placement.rcNormalPosition.left,
        placement.rcNormalPosition.top,
        placement.rcNormalPosition.right,
        placement.rcNormalPosition.bottom,
    };
    ::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                     &monitor);
    ::SetWindowLongPtr(window, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
    auto start = RECT{};
    ::GetWindowRect(window, &start);
    ::SetWindowPos(window, HWND_TOP, start.left, start.top,
                   start.right - start.left, start.bottom - start.top,
                   SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER |
                       SWP_FRAMECHANGED);
    const auto end = RECT{monitor.rcMonitor.left, monitor.rcMonitor.top,
                          monitor.rcMonitor.right, monitor.rcMonitor.bottom};
    StartTransition(window, start, end, std::move(completion));
  } else if (completion) {
    completion();
  }
}

void FullscreenUtils::ExitNativeFullscreen(HWND window, Completion completion) {
  if (!fullscreen_) {
    if (completion) {
      completion();
    }
    return;
  }
  fullscreen_ = false;

  auto style = ::GetWindowLongPtr(window, GWL_STYLE);
  if (!(style & WS_OVERLAPPEDWINDOW)) {
    ::SetWindowLongPtr(window, GWL_STYLE, style | WS_OVERLAPPEDWINDOW);
    if (::IsZoomed(window)) {
      // Refresh the parent window.
      ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                     SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                         SWP_FRAMECHANGED);
      auto rect = RECT{};
      ::GetClientRect(window, &rect);
      auto flutter_view =
          ::FindWindowEx(window, nullptr, kFlutterViewWindowClassName, nullptr);
      ::SetWindowPos(flutter_view, nullptr, rect.left, rect.top,
                     rect.right - rect.left, rect.bottom - rect.top,
                     SWP_NOACTIVATE | SWP_NOZORDER);
      if (completion) {
        completion();
      }
    } else {
      auto start = RECT{};
      ::GetWindowRect(window, &start);
      ::SetWindowPos(window, nullptr, start.left, start.top,
                     start.right - start.left, start.bottom - start.top,
                     SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER |
                         SWP_FRAMECHANGED);
      StartTransition(window, start, rect_before_fullscreen_,
                      std::move(completion));
    }
  } else if (completion) {
    completion();
  }
}

void FullscreenUtils::StartTransition(HWND window, const RECT& start,
                                      const RECT& end,
                                      Completion completion) {
  transition_active_ = true;
  transition_window_ = window;
  transition_start_ = start;
  transition_end_ = end;
  transition_started_at_ = ::GetTickCount64();
  transition_completion_ = std::move(completion);
  if (::SetTimer(window, kTransitionTimerId, 16, TransitionTimerProc) == 0) {
    // 定时器创建失败时仍完成状态切换，避免 Dart 通道一直等待。
    FinishTransition();
  }
}

void FullscreenUtils::FinishTransition() {
  if (!transition_active_) {
    return;
  }
  ::KillTimer(transition_window_, kTransitionTimerId);
  ::SetWindowPos(transition_window_, nullptr, transition_end_.left,
                 transition_end_.top,
                 transition_end_.right - transition_end_.left,
                 transition_end_.bottom - transition_end_.top,
                 SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER |
                     SWP_FRAMECHANGED);
  transition_active_ = false;
  auto completion = std::move(transition_completion_);
  transition_window_ = nullptr;
  if (completion) {
    completion();
  }
}

void CALLBACK FullscreenUtils::TransitionTimerProc(HWND window, UINT message,
                                                   UINT_PTR timer_id,
                                                   DWORD tick) {
  if (timer_id != kTransitionTimerId || !transition_active_ ||
      window != transition_window_) {
    return;
  }
  const auto elapsed = ::GetTickCount64() - transition_started_at_;
  const auto linear = std::min(
      1.0, static_cast<double>(elapsed) / kTransitionDurationMs);
  const auto progress = linear < 0.5
                            ? 4.0 * linear * linear * linear
                            : 1.0 - std::pow(-2.0 * linear + 2.0, 3.0) / 2.0;
  const auto left = Interpolate(transition_start_.left, transition_end_.left,
                                progress);
  const auto top = Interpolate(transition_start_.top, transition_end_.top,
                               progress);
  const auto right = Interpolate(transition_start_.right, transition_end_.right,
                                 progress);
  const auto bottom = Interpolate(transition_start_.bottom,
                                  transition_end_.bottom, progress);
  ::SetWindowPos(window, nullptr, left, top, right - left, bottom - top,
                 SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER);
  if (linear >= 1.0) {
    FinishTransition();
  }
}

LONG FullscreenUtils::Interpolate(LONG start, LONG end, double progress) {
  return static_cast<LONG>(std::lround(
      static_cast<double>(start) + (end - start) * progress));
}

bool FullscreenUtils::fullscreen_ = false;

RECT FullscreenUtils::rect_before_fullscreen_ = RECT{};
bool FullscreenUtils::transition_active_ = false;
RECT FullscreenUtils::transition_start_ = RECT{};
RECT FullscreenUtils::transition_end_ = RECT{};
ULONGLONG FullscreenUtils::transition_started_at_ = 0;
HWND FullscreenUtils::transition_window_ = nullptr;
FullscreenUtils::Completion FullscreenUtils::transition_completion_ = {};
