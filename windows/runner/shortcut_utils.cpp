// shortcut_utils.cpp - Windows desktop shortcut utilities

#include "shortcut_utils.h"

#include <shobjidl.h>
#include <shlobj.h>
#include <propkey.h>
#include <propvarutil.h>
#include <appmodel.h>

#include <optional>
#include <vector>

namespace {

bool GetDesktopShortcutPath(const std::wstring& shortcutName,
                            std::wstring* shortcutPath) {
  PWSTR desktopPath = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_Desktop, KF_FLAG_DEFAULT, nullptr,
                                  &desktopPath))) {
    return false;
  }
  *shortcutPath =
      std::wstring(desktopPath) + L"\\" + shortcutName + L".lnk";
  CoTaskMemFree(desktopPath);
  return true;
}

std::optional<bool> ShortcutFileExists(const std::wstring& shortcutPath) {
  const DWORD attributes = GetFileAttributesW(shortcutPath.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES) {
    return (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
  }
  const DWORD error = GetLastError();
  if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
    return false;
  }
  return std::nullopt;
}

std::optional<bool> KnownFolderShortcutExists(
    REFKNOWNFOLDERID folderId,
    const std::wstring& shortcutName) {
  PWSTR folderPath = nullptr;
  if (FAILED(SHGetKnownFolderPath(folderId, KF_FLAG_DEFAULT, nullptr,
                                  &folderPath))) {
    return std::nullopt;
  }
  const std::wstring shortcutPath =
      std::wstring(folderPath) + L"\\" + shortcutName + L".lnk";
  CoTaskMemFree(folderPath);
  return ShortcutFileExists(shortcutPath);
}

std::optional<bool> PackagedStartMenuEntryExists() {
  UINT32 length = 0;
  const LONG firstResult = GetCurrentPackageFamilyName(&length, nullptr);
  if (firstResult == APPMODEL_ERROR_NO_PACKAGE) return false;
  if (firstResult != ERROR_INSUFFICIENT_BUFFER || length == 0) {
    return std::nullopt;
  }

  std::vector<wchar_t> familyName(length);
  if (GetCurrentPackageFamilyName(&length, familyName.data()) !=
      ERROR_SUCCESS) {
    return std::nullopt;
  }
  return true;
}

std::optional<bool> StartMenuEntryExists(
    const std::wstring& shortcutName) {
  const auto packaged = PackagedStartMenuEntryExists();
  if (!packaged.has_value()) return std::nullopt;
  if (packaged.value()) return true;

  const auto currentUser =
      KnownFolderShortcutExists(FOLDERID_Programs, shortcutName);
  if (currentUser.has_value() && currentUser.value()) return true;
  const auto allUsers =
      KnownFolderShortcutExists(FOLDERID_CommonPrograms, shortcutName);
  if (allUsers.has_value() && allUsers.value()) return true;
  if (!currentUser.has_value() || !allUsers.has_value()) return std::nullopt;
  return false;
}

}  // namespace

std::optional<ShortcutEntryState> ShortcutUtils::InspectShortcutEntries(
    const std::wstring& shortcutName) {
  std::wstring desktopShortcutPath;
  if (!GetDesktopShortcutPath(shortcutName, &desktopShortcutPath)) {
    return std::nullopt;
  }
  const auto desktopExists = ShortcutFileExists(desktopShortcutPath);
  const auto startMenuExists = StartMenuEntryExists(shortcutName);
  if (!desktopExists.has_value() || !startMenuExists.has_value()) {
    return std::nullopt;
  }

  const int state = (desktopExists.value() ? 1 : 0) |
                    (startMenuExists.value() ? 2 : 0);
  return static_cast<ShortcutEntryState>(state);
}

bool ShortcutUtils::DesktopShortcutExists(
    const std::wstring& shortcutName) {
  std::wstring shortcutPath;
  if (!GetDesktopShortcutPath(shortcutName, &shortcutPath)) return false;
  return ShortcutFileExists(shortcutPath).value_or(false);
}

bool ShortcutUtils::CreateDesktopShortcut(const std::wstring& shortcutName, const std::wstring& description) {
  std::wstring shortcutPath;
  if (!GetDesktopShortcutPath(shortcutName, &shortcutPath)) return false;

  // COM is already initialized in main.cpp, do not re-initialize
  IShellLinkW* pShellLink = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, (void**)&pShellLink);
  if (FAILED(hr)) return false;

  pShellLink->SetDescription(description.c_str());

  wchar_t exePath[MAX_PATH];
  const DWORD exePathLength = GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  if (exePathLength == 0 || exePathLength >= MAX_PATH) {
    pShellLink->Release();
    return false;
  }
  pShellLink->SetIconLocation(exePath, 0);

  // Check if running as MSIX package
  UINT32 length = 0;
  std::wstring aumid;
  if (GetCurrentPackageFamilyName(&length, nullptr) == ERROR_INSUFFICIENT_BUFFER) {
    aumid.resize(length);
    if (GetCurrentPackageFamilyName(&length, &aumid[0]) == ERROR_SUCCESS) {
      if (!aumid.empty() && aumid.back() == L'\0') aumid.pop_back();
      aumid += L"!kanyingyin";
    }
  }

  bool success = false;
  IPersistFile* pPersistFile = nullptr;

  if (!aumid.empty()) {
    // MSIX: let Explorer launch the current package application.
    wchar_t windowsPath[MAX_PATH];
    if (GetWindowsDirectoryW(windowsPath, MAX_PATH) == 0) {
      pShellLink->Release();
      return false;
    }
    const std::wstring explorerPath =
        std::wstring(windowsPath) + L"\\explorer.exe";
    const std::wstring arguments = L"shell:AppsFolder\\" + aumid;
    pShellLink->SetPath(explorerPath.c_str());
    pShellLink->SetArguments(arguments.c_str());

    IPropertyStore* pPropertyStore = nullptr;
    if (SUCCEEDED(pShellLink->QueryInterface(IID_IPropertyStore, (void**)&pPropertyStore))) {
      PROPVARIANT propVar;
      if (SUCCEEDED(InitPropVariantFromString(aumid.c_str(), &propVar))) {
        pPropertyStore->SetValue(PKEY_AppUserModel_ID, propVar);
        PropVariantClear(&propVar);
      }
      pPropertyStore->Commit();
      pPropertyStore->Release();
    }
  } else {
    // Portable: use executable path
    pShellLink->SetPath(exePath);
    pShellLink->SetArguments(L"");
  }

  if (SUCCEEDED(pShellLink->QueryInterface(IID_IPersistFile, (void**)&pPersistFile))) {
    success = SUCCEEDED(pPersistFile->Save(shortcutPath.c_str(), TRUE));
    pPersistFile->Release();
  }

  pShellLink->Release();
  return success;
}
