#include "external_player_utils.h"

#include <cstdlib>
#include <optional>
#include <string>

namespace {

void Require(bool condition) {
  if (!condition) std::abort();
}

struct FakeOperationState {
  std::wstring playlist_path = L"C:\\Temp\\playlist.m3u8";
  std::wstring written_target;
  std::wstring deleted_now;
  std::wstring deleted_later;
  bool create_path = true;
  bool write_success = true;
  bool launch_success = true;

  ExternalPlayerOperations BuildOperations() {
    return ExternalPlayerOperations{
        [this]() -> std::optional<std::wstring> {
          if (!create_path) return std::nullopt;
          return playlist_path;
        },
        [this](const std::wstring&, const std::wstring& target) {
          written_target = target;
          return write_success;
        },
        [this](const std::wstring&) { return launch_success; },
        [this](const std::wstring& path) { deleted_now = path; },
        [this](const std::wstring& path) { deleted_later = path; },
    };
  }
};

void TestUtf8ConversionSupportsChinesePath() {
  const auto converted =
      ExternalPlayerUtils::Utf8ToUtf16(u8R"(D:\视频\电影.mkv)");
  Require(converted.has_value());
  Require(converted.value() == L"D:\\视频\\电影.mkv");
  Require(!ExternalPlayerUtils::Utf8ToUtf16("\xFF").has_value());
}

void TestSuccessfulLaunchSchedulesDelayedCleanup() {
  FakeOperationState state;
  const auto status = ExternalPlayerUtils::OpenWithPlayer(
      u8R"(D:\视频\电影.mkv)", state.BuildOperations());

  Require(status == ExternalPlayerOpenStatus::kOpened);
  Require(state.written_target == L"D:\\视频\\电影.mkv");
  Require(state.deleted_now.empty());
  Require(state.deleted_later == state.playlist_path);
}

void TestLaunchFailureDeletesPlaylistImmediately() {
  FakeOperationState state;
  state.launch_success = false;
  const auto status = ExternalPlayerUtils::OpenWithPlayer(
      u8R"(D:\视频\电影.mkv)", state.BuildOperations());

  Require(status == ExternalPlayerOpenStatus::kLaunchFailed);
  Require(state.deleted_now == state.playlist_path);
  Require(state.deleted_later.empty());
}

void TestWriteFailureDeletesPlaylistImmediately() {
  FakeOperationState state;
  state.write_success = false;
  const auto status = ExternalPlayerUtils::OpenWithPlayer(
      u8R"(D:\视频\电影.mkv)", state.BuildOperations());

  Require(status == ExternalPlayerOpenStatus::kTemporaryFileFailed);
  Require(state.deleted_now == state.playlist_path);
  Require(state.deleted_later.empty());
}

}  // namespace

int main() {
  TestUtf8ConversionSupportsChinesePath();
  TestSuccessfulLaunchSchedulesDelayedCleanup();
  TestLaunchFailureDeletesPlaylistImmediately();
  TestWriteFailureDeletesPlaylistImmediately();
  return 0;
}
