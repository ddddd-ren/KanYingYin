// 看影音外部播放器工具。
//
// Copyright © 2024 Predidit
// All rights reserved.
// Use of this source code is governed by GPLv3 license that can be found in the
// LICENSE file.

#include "external_player_utils.h"

#include <windows.h>

#include <chrono>
#include <climits>
#include <cstdint>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr wchar_t kCleanupFailureMessage[] =
    L"看影音：外部播放临时文件清理失败\n";

std::optional<std::wstring> CreatePlaylistPath() {
  wchar_t temporary_directory[MAX_PATH];
  const DWORD directory_length =
      GetTempPathW(MAX_PATH, temporary_directory);
  if (directory_length == 0 || directory_length >= MAX_PATH) {
    return std::nullopt;
  }

  GUID guid;
  if (FAILED(CoCreateGuid(&guid))) return std::nullopt;

  wchar_t guid_text[39];
  if (StringFromGUID2(guid, guid_text, 39) == 0) return std::nullopt;

  return std::wstring(temporary_directory) + L"kanyingyin_stream_" +
         guid_text + L".m3u8";
}

std::optional<std::string> Utf16ToUtf8(std::wstring_view value) {
  if (value.empty() || value.size() > static_cast<size_t>(INT_MAX)) {
    return std::nullopt;
  }
  const int input_length = static_cast<int>(value.size());
  const int output_length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), input_length, nullptr, 0,
      nullptr, nullptr);
  if (output_length <= 0) return std::nullopt;

  std::string output(static_cast<size_t>(output_length), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                          input_length, output.data(), output_length, nullptr,
                          nullptr) != output_length) {
    return std::nullopt;
  }
  return output;
}

bool WritePlaylist(const std::wstring& path, const std::wstring& target) {
  const auto utf8_target = Utf16ToUtf8(target);
  if (!utf8_target.has_value()) return false;

  const std::string content =
      std::string("\xEF\xBB\xBF#EXTM3U\r\n") + utf8_target.value() + "\r\n";
  const HANDLE file = CreateFileW(
      path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_TEMPORARY | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;

  DWORD bytes_written = 0;
  const bool success =
      content.size() <= static_cast<size_t>(MAXDWORD) &&
      WriteFile(file, content.data(), static_cast<DWORD>(content.size()),
                &bytes_written, nullptr) != FALSE &&
      bytes_written == content.size();
  CloseHandle(file);
  return success;
}

bool LaunchPlaylist(const std::wstring& path) {
  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(SHELLEXECUTEINFOW);
  execute_info.fMask = SEE_MASK_INVOKEIDLIST | SEE_MASK_FLAG_NO_UI;
  execute_info.lpVerb = L"openas";
  execute_info.lpFile = path.c_str();
  execute_info.nShow = SW_SHOWNORMAL;
  return ShellExecuteExW(&execute_info) != FALSE;
}

void DeletePlaylist(const std::wstring& path) {
  if (DeleteFileW(path.c_str()) == FALSE &&
      GetLastError() != ERROR_FILE_NOT_FOUND) {
    OutputDebugStringW(kCleanupFailureMessage);
  }
}

void DeletePlaylistLater(const std::wstring& path) {
  std::thread([path]() {
    std::this_thread::sleep_for(std::chrono::seconds(30));
    DeletePlaylist(path);
  }).detach();
}

ExternalPlayerOperations BuildWindowsOperations() {
  return ExternalPlayerOperations{
      CreatePlaylistPath,
      WritePlaylist,
      LaunchPlaylist,
      DeletePlaylist,
      DeletePlaylistLater,
  };
}

}  // namespace

std::optional<std::wstring> ExternalPlayerUtils::Utf8ToUtf16(
    std::string_view value) {
  if (value.empty() || value.size() > static_cast<size_t>(INT_MAX)) {
    return std::nullopt;
  }
  const int input_length = static_cast<int>(value.size());
  const int output_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_length, nullptr, 0);
  if (output_length <= 0) return std::nullopt;

  std::wstring output(static_cast<size_t>(output_length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          input_length, output.data(), output_length) !=
      output_length) {
    return std::nullopt;
  }
  return output;
}

ExternalPlayerOpenStatus ExternalPlayerUtils::OpenWithPlayer(
    const std::string& url) {
  return OpenWithPlayer(url, BuildWindowsOperations());
}

ExternalPlayerOpenStatus ExternalPlayerUtils::OpenWithPlayer(
    const std::string& url,
    const ExternalPlayerOperations& operations) {
  const auto target = Utf8ToUtf16(url);
  if (!target.has_value()) return ExternalPlayerOpenStatus::kInvalidUtf8;

  const auto playlist_path = operations.create_playlist_path();
  if (!playlist_path.has_value()) {
    return ExternalPlayerOpenStatus::kTemporaryFileFailed;
  }
  if (!operations.write_playlist(playlist_path.value(), target.value())) {
    operations.delete_now(playlist_path.value());
    return ExternalPlayerOpenStatus::kTemporaryFileFailed;
  }
  if (!operations.launch(playlist_path.value())) {
    operations.delete_now(playlist_path.value());
    return ExternalPlayerOpenStatus::kLaunchFailed;
  }

  operations.delete_later(playlist_path.value());
  return ExternalPlayerOpenStatus::kOpened;
}
