#include "fullscreen_utils.h"

#include <cstdlib>
#include <iostream>

namespace {
void Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << message << std::endl;
    std::exit(1);
  }
}

template <typename Predicate>
void PumpUntil(Predicate completed) {
  const auto deadline = ::GetTickCount64() + 3000;
  while (!completed() && ::GetTickCount64() < deadline) {
    MSG message{};
    while (::PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      ::TranslateMessage(&message);
      ::DispatchMessage(&message);
    }
    if (!completed()) {
      ::MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
    }
  }
  Check(completed(), "fullscreen completion timed out");
}

HWND CreateTestWindow() {
  const auto window = ::CreateWindowEx(
      0, L"KanYingYinFullscreenTest", L"fullscreen test",
      WS_OVERLAPPEDWINDOW, 120, 100, 640, 480, nullptr, nullptr,
      ::GetModuleHandle(nullptr), nullptr);
  Check(window != nullptr, "test window creation failed");
  return window;
}

void RoundTrip(bool maximized) {
  const auto window = CreateTestWindow();
  if (maximized) {
    // 隐藏窗口验证最大化状态分支，不改变用户桌面焦点。
    ::SetWindowLongPtr(window, GWL_STYLE,
                       ::GetWindowLongPtr(window, GWL_STYLE) | WS_MAXIMIZE);
  }
  RECT before{};
  ::GetWindowRect(window, &before);
  bool entered = false;
  FullscreenUtils::EnterNativeFullscreen(window, [&] { entered = true; });
  Check(!entered, "enter completion must wait for animation");
  PumpUntil([&] { return entered; });
  bool exited = false;
  FullscreenUtils::ExitNativeFullscreen(window, [&] { exited = true; });
  Check(!exited, "exit completion must wait even when maximized");
  PumpUntil([&] { return exited; });
  RECT after{};
  ::GetWindowRect(window, &after);
  Check(::EqualRect(&before, &after), "window bounds were not restored");
  Check((::IsZoomed(window) != FALSE) == maximized,
        "maximized state was not restored");
  ::DestroyWindow(window);
}

void InterruptedTransition() {
  const auto window = CreateTestWindow();
  int completions = 0;
  FullscreenUtils::EnterNativeFullscreen(window, [&] { ++completions; });
  FullscreenUtils::EnterNativeFullscreen(window, [&] { ++completions; });
  Check(completions == 0, "duplicate enter completed before animation");
  FullscreenUtils::ExitNativeFullscreen(window, [&] { ++completions; });
  PumpUntil([&] { return completions == 3; });
  Check((::GetWindowLongPtr(window, GWL_STYLE) & WS_OVERLAPPEDWINDOW) != 0,
        "interrupted transition did not restore window style");
  ::DestroyWindow(window);
}
}  // namespace

int main() {
  WNDCLASS window_class{};
  window_class.lpfnWndProc = ::DefWindowProc;
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.lpszClassName = L"KanYingYinFullscreenTest";
  Check(::RegisterClass(&window_class) != 0, "window class registration failed");
  RoundTrip(false);
  RoundTrip(true);
  InterruptedTransition();
  std::cout << "3 native fullscreen scenarios passed" << std::endl;
  return 0;
}
