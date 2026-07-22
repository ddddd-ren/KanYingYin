[CmdletBinding()]
param(
  [string]$FlutterPath = 'D:\flutter\bin\flutter.bat',
  [string]$DartPath = 'D:\flutter\bin\dart.bat',
  [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.kanyingyin\signing'),
  [string]$DesktopDirectory = (Join-Path $env:USERPROFILE 'Desktop')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temporaryRoot = Join-Path $env:TEMP ("kanyingyin-public-release-{0}" -f [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $temporaryRoot 'package'
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$generatedMsix = Join-Path $releaseDirectory 'kanyingyin.msix'
$pfxPath = Join-Path $SigningDirectory 'certificate.pfx'
$passwordPath = Join-Path $SigningDirectory 'certificate-password.clixml'
$plainPassword = $null
$passwordPointer = [IntPtr]::Zero

function Assert-PublicTemporaryRoot {
  $temporaryBase = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
  $candidate = [System.IO.Path]::GetFullPath($temporaryRoot)
  if (-not $candidate.StartsWith($temporaryBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw '公共构建临时目录不在当前用户临时目录内'
  }
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "命令执行失败（退出码 $LASTEXITCODE）：$Executable"
  }
}

function Get-PubspecValue {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $line = $Lines | Where-Object { $_ -match $Pattern } | Select-Object -First 1
  if ($null -eq $line) { throw "pubspec.yaml 缺少 $Name" }
  $match = [regex]::Match($line, $Pattern)
  if (-not $match.Success) { throw "pubspec.yaml 中的 $Name 格式无效" }
  return $match.Groups[1].Value
}

function Get-SignToolPath {
  $candidates = @(Get-ChildItem -LiteralPath "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
      -Filter 'signtool.exe' -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
      Sort-Object FullName -Descending)
  if ($candidates.Count -eq 0) { throw '未找到 Windows SDK x64 SignTool' }
  return $candidates[0].FullName
}

$runningProcesses = @(Get-Process -Name 'kanyingyin' -ErrorAction SilentlyContinue |
    Where-Object { -not $_.HasExited })
if ($runningProcesses.Count -gt 0) {
  throw '请先退出正在运行的看影音，再生成签名安装包'
}
foreach ($requiredPath in @($FlutterPath, $DartPath, $pfxPath, $passwordPath)) {
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "缺少构建所需文件：$requiredPath"
  }
}
if (-not (Test-Path -LiteralPath $DesktopDirectory -PathType Container)) {
  throw "桌面目录不存在：$DesktopDirectory"
}

$pubspecLines = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Encoding UTF8
$versionWithBuild = Get-PubspecValue -Lines $pubspecLines -Pattern '^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$' -Name '应用版本'
$msixVersion = Get-PubspecValue -Lines $pubspecLines -Pattern '^\s*msix_version:\s*(\d+\.\d+\.\d+\.\d+)\s*$' -Name 'MSIX 版本'
if ($msixVersion -ne "$versionWithBuild.0") {
  throw "应用版本与 MSIX 版本不一致：$versionWithBuild / $msixVersion"
}

$desktopMsix = Join-Path $DesktopDirectory "看影音-$versionWithBuild.msix"
$desktopZip = Join-Path $DesktopDirectory "看影音-$versionWithBuild-异机安装包.zip"
Assert-PublicTemporaryRoot

try {
  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
  $acl = Get-Acl -LiteralPath $temporaryRoot
  $acl.SetAccessRuleProtection($true, $false)
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $identity,
    'FullControl',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow'
  )
  $acl.SetAccessRule($rule)
  Set-Acl -LiteralPath $temporaryRoot -AclObject $acl

  Push-Location $projectRoot
  try {
    Invoke-Checked -Executable $FlutterPath -Arguments @('build', 'windows', '--release', '--no-pub')

    $releaseExecutable = Join-Path $releaseDirectory 'kanyingyin.exe'
    $releaseApp = Join-Path $releaseDirectory 'data\app.so'
    foreach ($releaseArtifact in @($releaseExecutable, $releaseApp)) {
      if (-not (Test-Path -LiteralPath $releaseArtifact -PathType Leaf)) {
        throw "Windows Release 缺少本轮产物：$releaseArtifact"
      }
      $releaseInfo = Get-Item -LiteralPath $releaseArtifact
      if ($releaseInfo.Length -le 0) {
        throw "Windows Release 产物为空：$releaseArtifact"
      }
    }

    if (Test-Path -LiteralPath $generatedMsix) {
      Remove-Item -LiteralPath $generatedMsix -Force
    }
    Invoke-Checked -Executable $DartPath -Arguments @(
      'run', 'msix:create', '--build-windows', 'false', '--output-name', 'kanyingyin'
    )
  } finally {
    Pop-Location
  }

  if (-not (Test-Path -LiteralPath $generatedMsix -PathType Leaf)) {
    throw 'MSIX 封装完成后未找到 kanyingyin.msix'
  }

  $securePassword = Import-Clixml -LiteralPath $passwordPath
  if ($securePassword -isnot [System.Security.SecureString]) {
    throw '签名密码文件不是当前用户可读取的 SecureString'
  }
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
  $signTool = Get-SignToolPath
  Invoke-Checked -Executable $signTool -Arguments @(
    'sign', '/fd', 'SHA256', '/a', '/f', $pfxPath, '/p', $plainPassword, $generatedMsix
  )
  Invoke-Checked -Executable $signTool -Arguments @('verify', '/pa', '/v', $generatedMsix)

  $signature = Get-AuthenticodeSignature -LiteralPath $generatedMsix
  if ($signature.Status -ne 'Valid') { throw '生成的 MSIX 签名状态无效' }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  Add-Type -AssemblyName System.Xml.Linq
  $archive = [System.IO.Compression.ZipFile]::OpenRead($generatedMsix)
  try {
    $manifestEntry = $archive.Entries |
      Where-Object { $_.FullName -eq 'AppxManifest.xml' } |
      Select-Object -First 1
    if ($null -eq $manifestEntry) { throw 'MSIX 中缺少 AppxManifest.xml' }
    $stream = $manifestEntry.Open()
    try {
      $manifest = [System.Xml.Linq.XDocument]::Load($stream)
    } finally {
      $stream.Dispose()
    }
  } finally {
    $archive.Dispose()
  }
  $manifestIdentity = $manifest.Root.Elements() |
    Where-Object { $_.Name.LocalName -eq 'Identity' } |
    Select-Object -First 1
  if ($null -eq $manifestIdentity) { throw 'MSIX 清单缺少 Identity' }
  if ($manifestIdentity.Attribute('Name').Value -ne 'com.kanyingyin.player' -or
      $manifestIdentity.Attribute('Publisher').Value -ne 'CN=KanYingYin' -or
      $manifestIdentity.Attribute('Version').Value -ne $msixVersion -or
      $manifestIdentity.Attribute('ProcessorArchitecture').Value -ne 'x64') {
    throw 'MSIX 清单身份、发布者、版本或架构验证失败'
  }

  Copy-Item -LiteralPath $generatedMsix -Destination $desktopMsix -Force
  $desktopHash = (Get-FileHash -LiteralPath $desktopMsix -Algorithm SHA256).Hash
  $sourceHash = (Get-FileHash -LiteralPath $generatedMsix -Algorithm SHA256).Hash
  if ($desktopHash -ne $sourceHash) { throw '桌面 MSIX 与构建产物哈希不一致' }

  $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $pfxPath,
    $plainPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
  )

  # ZIP清单开始
  $packageNames = @(
    "看影音-$versionWithBuild.msix",
    '看影音.cer',
    '安装看影音.ps1',
    '安装看影音.cmd',
    '安装说明.txt',
    'SHA256.txt'
  )
  # ZIP清单结束

  Copy-Item -LiteralPath $desktopMsix -Destination (Join-Path $packageRoot $packageNames[0])
  [System.IO.File]::WriteAllBytes(
    (Join-Path $packageRoot $packageNames[1]),
    $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
  )
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\安装看影音.ps1') `
    -Destination (Join-Path $packageRoot $packageNames[2])
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer\安装看影音.cmd') `
    -Destination (Join-Path $packageRoot $packageNames[3])
  $publicInstructions = @'
看影音签名安装包

1. 请完整解压 ZIP，不要单独移动其中的文件。
2. 双击“安装看影音.cmd”。脚本会先验证安装包哈希、清单身份和数字签名。
3. 安装脚本只把看影音公钥证书导入当前用户的 TrustedPeople，不修改本机范围证书存储。
4. 安装完成后从开始菜单启动“看影音”。首次启动会按应用提示询问是否创建快捷方式。

本安装包不内置 TMDB Key。你可以在设置中填写自己的 Key；没有 Key 或断网时，本地扫描和播放仍可使用。
看影音不会修改或删除本地原始媒体，也不会修改网盘文件、目录或远程 ID。
'@
  Set-Content -LiteralPath (Join-Path $packageRoot $packageNames[4]) `
    -Value $publicInstructions -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $packageRoot $packageNames[5]) `
    -Value "$desktopHash  $($packageNames[0])" -Encoding UTF8

  $actualPackageNames = @(Get-ChildItem -LiteralPath $packageRoot -File |
      Select-Object -ExpandProperty Name |
      Sort-Object)
  $expectedPackageNames = @($packageNames | Sort-Object)
  if (Compare-Object -ReferenceObject $expectedPackageNames -DifferenceObject $actualPackageNames) {
    throw '异机安装包暂存目录包含非固定清单文件'
  }
  if (Test-Path -LiteralPath $desktopZip) {
    Remove-Item -LiteralPath $desktopZip -Force
  }
  Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $packageRoot -File).FullName `
    -DestinationPath $desktopZip -CompressionLevel Optimal

  Write-Host "签名 MSIX：$desktopMsix"
  Write-Host "异机安装包：$desktopZip"
  Write-Host "MSIX SHA256：$desktopHash"
} finally {
  if ($passwordPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $passwordPointer = [IntPtr]::Zero
  }
  $plainPassword = $null
  if (Test-Path -LiteralPath $temporaryRoot) {
    Assert-PublicTemporaryRoot
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
  if (Test-Path -LiteralPath $temporaryRoot) {
    throw '公共构建临时目录清理失败'
  }
}
