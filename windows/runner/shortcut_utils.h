// shortcut_utils.h - Windows 快捷方式工具

#ifndef SHORTCUT_UTILS_H_
#define SHORTCUT_UTILS_H_

#include <optional>
#include <string>

enum class ShortcutEntryState {
  kNone = 0,
  kDesktopOnly = 1,
  kStartMenuOnly = 2,
  kDesktopAndStartMenu = 3,
};

class ShortcutUtils {
 public:
  static std::optional<ShortcutEntryState> InspectShortcutEntries(
      const std::wstring& shortcut_name);
  static bool DesktopShortcutExists(const std::wstring& shortcut_name);
  static bool CreateDesktopShortcut(const std::wstring& shortcut_name,
                                    const std::wstring& description);
};

#endif  // SHORTCUT_UTILS_H_
