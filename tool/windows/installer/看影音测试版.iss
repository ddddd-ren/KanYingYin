#ifndef MyAppVersion
  #define MyAppVersion "2.1.169"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define MyAppName "看影音"
#define MyAppPublisher "看影音"
#define MyAppExeName "kanyingyin.exe"

[Setup]
AppId={{50DD11C1-8DE7-4C2F-87F1-82D53B9D2C54}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={code:DefaultInstallDir}
DisableDirPage=no
AppendDefaultDirName=no
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=看影音-{#MyAppVersion}-测试版-安装程序
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.msix,msix_verify_*\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载{#MyAppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动{#MyAppName}并验证安装"; Flags: nowait postinstall skipifsilent

[Code]
function DefaultInstallDir(Param: String): String;
begin
  Result := ExpandConstant('{localappdata}\Programs\看影音');
end;
