// 看影音外部播放器工具。
//
// Copyright © 2024 Predidit
// All rights reserved.
// Use of this source code is governed by GPLv3 license that can be found in the
// LICENSE file.

#ifndef EXTERNAL_PLAYER_UTILS_H_
#define EXTERNAL_PLAYER_UTILS_H_

#include <functional>
#include <optional>
#include <string>
#include <string_view>

enum class ExternalPlayerOpenStatus {
  kOpened,
  kInvalidUtf8,
  kTemporaryFileFailed,
  kLaunchFailed,
};

struct ExternalPlayerOperations {
  std::function<std::optional<std::wstring>()> create_playlist_path;
  std::function<bool(const std::wstring&, const std::wstring&)> write_playlist;
  std::function<bool(const std::wstring&)> launch;
  std::function<void(const std::wstring&)> delete_now;
  std::function<void(const std::wstring&)> delete_later;
};

class ExternalPlayerUtils {
 public:
  static std::optional<std::wstring> Utf8ToUtf16(std::string_view value);

  static ExternalPlayerOpenStatus OpenWithPlayer(const std::string& url);

  static ExternalPlayerOpenStatus OpenWithPlayer(
      const std::string& url,
      const ExternalPlayerOperations& operations);
};

#endif  // EXTERNAL_PLAYER_UTILS_H_
