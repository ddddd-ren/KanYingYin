#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include "external_player_utils.h"
#include "fullscreen_utils.h"
#include "shortcut_utils.h"

void FlutterWindow::RegisterIntentChannel() {
  auto window_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.kanyingyin.player/intent",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name().compare("enterFullscreen") == 0) {
      FullscreenUtils::EnterNativeFullscreen(GetHandle());
      result->Success();
    } else if (call.method_name().compare("exitFullscreen") == 0) {
      FullscreenUtils::ExitNativeFullscreen(GetHandle());
      result->Success();
    } else if (call.method_name().compare("openWithMime") == 0) {
      const auto* arguments =
          std::get_if<flutter::EncodableMap>(call.arguments());
      if (arguments) {
        auto url_it = arguments->find(flutter::EncodableValue("url"));
        if (url_it != arguments->end()) {
          const std::string& url = std::get<std::string>(url_it->second);
          ExternalPlayerUtils::OpenWithPlayer(url.c_str());
          result->Success();
        } else {
          result->Error("InvalidArguments", "Missing 'url' argument");
        }
      } else {
        result->Error("InvalidArguments", "Arguments are not a map");
      }
    } else {
      result->NotImplemented();
    }
  });
}

void FlutterWindow::RegisterStorageChannel() {
  auto storage_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.kanyingyin.player/storage",
          &flutter::StandardMethodCodec::GetInstance());

  storage_channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name().compare("getAvailableStorage") == 0) {
      std::wstring path = L"C:\\";
      const auto* arguments =
          std::get_if<flutter::EncodableMap>(call.arguments());
      if (arguments) {
        auto path_it = arguments->find(flutter::EncodableValue("path"));
        if (path_it != arguments->end()) {
          const std::string& path_str = std::get<std::string>(path_it->second);
          // Extract drive root, e.g. "C:\Users\..." -> "C:\"
          if (path_str.length() >= 2 && path_str[1] == ':') {
            path = std::wstring(1, static_cast<wchar_t>(path_str[0])) + L":\\";
          }
        }
      }

      ULARGE_INTEGER free_bytes_available;
      if (GetDiskFreeSpaceExW(path.c_str(), &free_bytes_available, nullptr,
                              nullptr)) {
        result->Success(flutter::EncodableValue(
            static_cast<int64_t>(free_bytes_available.QuadPart)));
      } else {
        result->Success(flutter::EncodableValue(static_cast<int64_t>(-1)));
      }
    } else {
      result->NotImplemented();
    }
  });
}

void FlutterWindow::RegisterShortcutChannel() {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.kanyingyin.player/shortcut",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler([](const auto& call, auto result) {
    constexpr wchar_t kShortcutName[] = L"\x770B\x5F71\x97F3";
    constexpr wchar_t kShortcutDescription[] =
        L"\x542F\x52A8\x770B\x5F71\x97F3";

    if (call.method_name() == "desktopShortcutExists") {
      result->Success(flutter::EncodableValue(
          ShortcutUtils::DesktopShortcutExists(kShortcutName)));
      return;
    }

    if (call.method_name() == "createDesktopShortcut") {
      const bool success = ShortcutUtils::CreateDesktopShortcut(
          kShortcutName, kShortcutDescription);
      if (success) {
        result->Success(flutter::EncodableValue(true));
      } else {
        result->Error("Failed", "Failed to create desktop shortcut");
      }
      return;
    }

    result->NotImplemented();
  });
}
