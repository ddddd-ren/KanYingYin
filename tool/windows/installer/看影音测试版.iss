#ifndef MyAppVersion
  #define MyAppVersion "2.1.135"
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
var
  ExistingMsixInfo: String;

function DefaultInstallDir(Param: String): String;
begin
  if DirExists('D:\') then
    Result := 'D:\看影音'
  else
    Result := ExpandConstant('{localappdata}\Programs\看影音');
end;

function QueryExistingMsix(): String;
var
  ResultCode: Integer;
  OutputFile: String;
  CommandLine: String;
  RawOutput: AnsiString;
begin
  Result := '';
  OutputFile := ExpandConstant('{tmp}\kanyingyin-msix.txt');
  CommandLine := '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command "' +
    '$p=Get-AppxPackage -Name com.kanyingyin.player -ErrorAction SilentlyContinue;' +
    'if($p){($p.Version.ToString()+''|''+$p.InstallLocation)|Out-File -LiteralPath ''' +
    OutputFile + ''' -Encoding utf8}"';
  if Exec('powershell.exe', CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
     FileExists(OutputFile) then
  begin
    LoadStringFromFile(OutputFile, RawOutput);
    Result := String(RawOutput);
  end;
  Result := Trim(Result);
end;

procedure InitializeWizard();
begin
  ExistingMsixInfo := QueryExistingMsix();
  if ExistingMsixInfo <> '' then
    MsgBox('检测到已安装的 MSIX 版本：' + #13#10 + ExistingMsixInfo + #13#10#13#10 +
      '本安装器不会自动卸载旧版。安装完成后可由你确认是否卸载。',
      mbInformation, MB_OK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if (CurStep = ssPostInstall) and (ExistingMsixInfo <> '') then
  begin
    if MsgBox('测试版 EXE 已安装完成。是否卸载旧的 MSIX 版本？' + #13#10 +
      '选择“否”会保留旧版及其数据。', mbConfirmation, MB_YESNO) = IDYES then
    begin
      if not Exec('powershell.exe',
        '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command "' +
        'Get-AppxPackage -Name com.kanyingyin.player | Remove-AppxPackage"',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
        MsgBox('旧 MSIX 卸载未完成，但不影响当前 EXE 版本使用。', mbError, MB_OK);
    end;
  end;
end;
