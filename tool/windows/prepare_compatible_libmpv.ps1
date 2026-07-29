[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDirectory,

  [Parameter(Mandatory = $true)]
  [string]$ProbeMediaPath,

  [string]$ApplicationLogPath = (
    Join-Path $env:APPDATA 'com.kanyingyin\看影音\logs\kanyingyin.log'
  ),

  [string]$DestinationDirectory = (
    Join-Path $env:USERPROFILE (
      '.kanyingyin\windows\libmpv\20260730-ad59ff1b4-ffmpeg8.1.2-r2'
    )
  ),

  [int]$PgsSubtitleId = 11,

  [int]$PgsProbeStartSeconds = 939
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$bundleId = '20260730-ad59ff1b4-ffmpeg8.1.2-r2'
$expectedLibmpvSha256 =
  '6CC4EAA6E60128A4C61E7F1BF6FE79FD4BC40A2A4DDF9CBDEB3363C520599BBF'
$sourceRoot = [System.IO.Path]::GetFullPath($SourceDirectory)
$probeMedia = [System.IO.Path]::GetFullPath($ProbeMediaPath)
$applicationLog = [System.IO.Path]::GetFullPath($ApplicationLogPath)
$destinationRoot = [System.IO.Path]::GetFullPath($DestinationDirectory)
$destinationParent = Split-Path -Parent $destinationRoot
$stagingRoot = Join-Path $destinationParent (
  ".staging-$bundleId-$([Guid]::NewGuid().ToString('N'))"
)

function Assert-FileExists {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "缺少$Description：$Path"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )
  if ($Text.IndexOf(
      $Expected,
      [System.StringComparison]::Ordinal
    ) -lt 0) {
    throw "$Description未通过：缺少 $Expected"
  }
}

function Assert-NotContains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Forbidden,
    [Parameter(Mandatory = $true)][string]$Description
  )
  if ($Text.IndexOf(
      $Forbidden,
      [System.StringComparison]::Ordinal
    ) -ge 0) {
    throw "$Description未通过：发现 $Forbidden"
  }
}

function Invoke-MpvProbe {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Description
  )
  $previousPath = $env:PATH
  try {
    $env:PATH = "$sourceRoot;$previousPath"
    $output = (& (Join-Path $sourceRoot 'mpv.com') @Arguments 2>&1 |
        Out-String)
    if ($LASTEXITCODE -ne 0) {
      throw "$Description失败，mpv 退出码：$LASTEXITCODE"
    }
    return $output
  } finally {
    $env:PATH = $previousPath
  }
}

function Assert-PathWithin {
  param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$Parent,
    [Parameter(Mandatory = $true)][string]$Description
  )
  $parentPrefix = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
  $resolvedCandidate = [System.IO.Path]::GetFullPath($Candidate)
  if (-not $resolvedCandidate.StartsWith(
      $parentPrefix,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "$Description不在预期目录内：$resolvedCandidate"
  }
}

Assert-FileExists -Path $probeMedia -Description '真实媒体探测文件'
Assert-FileExists -Path $applicationLog -Description '应用联合验证日志'
Assert-FileExists -Path (Join-Path $sourceRoot 'mpv.com') `
  -Description 'mpv 探测程序'

$requiredDllNames = @(
  'libmpv-2.dll',
  'avcodec-62.dll',
  'avformat-62.dll',
  'avutil-60.dll',
  'swresample-6.dll',
  'swscale-9.dll'
)
$excludedApplicationDllNames = @(
  'dartjni.dll',
  'flutter_windows.dll',
  'WebView2Loader.dll'
)
foreach ($requiredDllName in $requiredDllNames) {
  Assert-FileExists -Path (Join-Path $sourceRoot $requiredDllName) `
    -Description '播放器运行库'
}

$actualLibmpvSha256 = (
  Get-FileHash -LiteralPath (Join-Path $sourceRoot 'libmpv-2.dll') `
    -Algorithm SHA256
).Hash
if ($actualLibmpvSha256 -ne $expectedLibmpvSha256) {
  throw 'libmpv-2.dll 不是已经完成联合验证的固定版本'
}

$trueHdOutput = Invoke-MpvProbe -Description 'TrueHD 解码探测' -Arguments @(
  '--no-config',
  '--msg-level=all=v',
  '--audio-spdif=',
  '--frames=1',
  '--ao=null',
  '--vo=null',
  '--aid=1',
  $probeMedia
)
Assert-Contains -Text $trueHdOutput -Expected 'Selected decoder: truehd' `
  -Description 'TrueHD 解码探测'
Assert-NotContains -Text $trueHdOutput -Forbidden '(no decoders)' `
  -Description 'TrueHD 解码探测'

$pgsOutput = Invoke-MpvProbe -Description 'PGS 字幕解码探测' -Arguments @(
  '--no-config',
  '--msg-level=all=v',
  "--start=$PgsProbeStartSeconds",
  '--frames=60',
  '--aid=no',
  "--sid=$PgsSubtitleId",
  '--ao=null',
  '--vo=null',
  $probeMedia
)
Assert-Contains -Text $pgsOutput -Expected 'Using subtitle decoder pgssub' `
  -Description 'PGS 字幕解码探测'

$logLines = Get-Content -LiteralPath $applicationLog -Encoding UTF8
$sessionStarts = @()
for ($index = 0; $index -lt $logLines.Count; $index++) {
  if ($logLines[$index] -match 'PlayerController: renderer=') {
    $sessionStarts += $index
  }
}
if ($sessionStarts.Count -eq 0) {
  throw '应用日志中没有播放器联合验证会话'
}
$latestSession = $logLines[$sessionStarts[-1]..($logLines.Count - 1)] -join "`n"
Assert-Contains -Text $latestSession `
  -Expected 'Using hardware decoding (d3d11va)' `
  -Description 'D3D11 直通硬件解码验证'
Assert-Contains -Text $latestSession `
  -Expected 'Selected decoder: truehd' `
  -Description '应用 TrueHD 解码验证'
Assert-Contains -Text $latestSession `
  -Expected 'Using subtitle decoder pgssub' `
  -Description '应用 PGS 字幕验证'
Assert-Contains -Text $latestSession `
  -Expected 'VO: [libmpv]' `
  -Description 'media-kit libmpv 渲染验证'
foreach ($forbiddenLog in @(
    'Could not create device',
    'mpv_render_context_render() not being called or stuck',
    "Failed to initialize a decoder for codec 'truehd'",
    'PlayerController: player error'
  )) {
  Assert-NotContains -Text $latestSession -Forbidden $forbiddenLog `
    -Description '应用联合验证'
}

if (Test-Path -LiteralPath $destinationRoot) {
  throw "目标组件目录已经存在，拒绝覆盖：$destinationRoot"
}
New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
Assert-PathWithin -Candidate $stagingRoot -Parent $destinationParent `
  -Description '临时组件目录'
Assert-PathWithin -Candidate $destinationRoot -Parent $destinationParent `
  -Description '目标组件目录'
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

try {
  $sourceDlls = @(
    Get-ChildItem -LiteralPath $sourceRoot -Filter '*.dll' -File |
      Where-Object {
        $_.Name -notmatch '_plugin\.dll$' -and
        $_.Name -notin $excludedApplicationDllNames
      }
  )
  if ($sourceDlls.Count -lt $requiredDllNames.Count) {
    throw '播放器运行库数量异常'
  }
  foreach ($sourceDll in $sourceDlls) {
    Copy-Item -LiteralPath $sourceDll.FullName -Destination $stagingRoot
  }

  $dllManifest = @(
    Get-ChildItem -LiteralPath $stagingRoot -Filter '*.dll' -File |
      Sort-Object Name |
      ForEach-Object {
        [ordered]@{
          name = $_.Name
          sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
      }
  )
  $manifest = [ordered]@{
    bundleId = $bundleId
    mpvCommit = 'ad59ff1b4a7479e15cb01a96f64ada4fb4df4951'
    ffmpegVersion = '8.1.2'
    libmpvSha256 = $actualLibmpvSha256
    capabilities = @(
      'media-kit-d3d11-render-api',
      'd3d11va-direct',
      'truehd',
      'hdmv-pgs-subtitle'
    )
    files = $dllManifest
  }
  $manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (
      Join-Path $stagingRoot 'kanyingyin-libmpv-manifest.json'
    ) -Encoding UTF8

  Move-Item -LiteralPath $stagingRoot -Destination $destinationRoot
} finally {
  if (Test-Path -LiteralPath $stagingRoot) {
    Assert-PathWithin -Candidate $stagingRoot -Parent $destinationParent `
      -Description '待清理临时组件目录'
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
}

Write-Host "已准备看影音 Windows 播放器组件：$destinationRoot"
Write-Host "组件 DLL 数量：$($sourceDlls.Count)"
Write-Host "libmpv SHA256：$actualLibmpvSha256"
