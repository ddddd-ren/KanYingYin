// shortcut_utils.cpp - Windows desktop shortcut utilities

#include "shortcut_utils.h"

#include <shobjidl.h>
#include <shlobj.h>
#include <propkey.h>
#include <propvarutil.h>
#include <appmodel.h>

namespace {

bool GetDesktopShortcutPath(const std::wstring& shortcutName,
                            std::wstring* shortcutPath) {
  wchar_t desktopPath[MAX_PATH];
  if (SHGetFolderPathW(nullptr, CSIDL_DESKTOP, nullptr, 0, desktopPath) !=
      S_OK) {
    return false;
  }
  *shortcutPath = std::wstring(desktopPath) + L"\\" + shortcutName + L".lnk";
  return true;
}

}  // namespace

bool ShortcutUtils::DesktopShortcutExists(
    const std::wstring& shortcutName) {
  std::wstring shortcutPath;
  if (!GetDesktopShortcutPath(shortcutName, &shortcutPath)) return false;
  const DWORD attributes = GetFileAttributesW(shortcutPath.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
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
