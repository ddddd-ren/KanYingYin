[CmdletBinding()]
param(
  [string]$Version,
  [string]$ReleaseDirectory,
  [string]$DesktopDirectory = (Join-Path $env:USERPROFILE 'Desktop'),
  [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($Version)) {
  $pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
  $pubspec = Get-Content -LiteralPath $pubspecPath -Raw -Encoding UTF8
  $versionMatch = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$'
  )
  if (-not $versionMatch.Success) {
    throw "Unable to read application version from $pubspecPath"
  }
  $Version = $versionMatch.Groups[1].Value
}
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
  $ReleaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
}
$releasePath = [System.IO.Path]::GetFullPath($ReleaseDirectory)
$desktopPath = [System.IO.Path]::GetFullPath($DesktopDirectory)
$scriptCandidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.iss' -File)
if ($scriptCandidates.Count -ne 1) {
  throw "Expected exactly one Inno Setup script, found $($scriptCandidates.Count)"
}
$scriptPath = $scriptCandidates[0].FullName

if (-not (Test-Path -LiteralPath (Join-Path $releasePath 'kanyingyin.exe') -PathType Leaf)) {
  throw "Invalid Windows Release directory: $releasePath"
}
if (-not (Test-Path -LiteralPath $desktopPath -PathType Container)) {
  throw "Desktop directory does not exist: $desktopPath"
}

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    $IsccPath = $command.Source
  } else {
    $candidates = @(
      (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
      (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    $IsccPath = $candidates | Where-Object {
      Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
  }
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or
    -not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
  throw 'Inno Setup 6 compiler ISCC.exe was not found'
}

$compileStartedAt = Get-Date
& $IsccPath "/DMyAppVersion=$Version" "/DBuildDir=$releasePath" `
  "/DOutputDir=$desktopPath" $scriptPath
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$installerCandidates = @(Get-ChildItem -LiteralPath $desktopPath -Filter "*$Version*.exe" -File | Where-Object {
  $_.LastWriteTime -ge $compileStartedAt.AddMinutes(-1) -and
  $_.VersionInfo.ProductVersion.StartsWith($Version, [System.StringComparison]::Ordinal)
})
if ($installerCandidates.Count -ne 1) {
  throw "Expected exactly one generated installer for $Version, found $($installerCandidates.Count)"
}
$installer = $installerCandidates[0]
$hash = Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
$signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
[PSCustomObject]@{
  Version = $Version
  Path = $installer.FullName
  Length = $installer.Length
  ProductVersion = $installer.VersionInfo.ProductVersion
  SHA256 = $hash.Hash
  SignatureStatus = $signature.Status
}
