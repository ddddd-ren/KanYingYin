[CmdletBinding()]
param(
  [string]$FlutterPath = 'D:\flutter\bin\flutter.bat',
  [string]$DesktopDirectory = (Join-Path $env:USERPROFILE 'Desktop'),
  [switch]$SkipBuild,
  [string[]]$BuildArguments = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw -Encoding UTF8
$versionMatch = [regex]::Match(
  $pubspec,
  '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$'
)
if (-not $versionMatch.Success) {
  throw "Unable to read application version from $pubspecPath"
}
$version = $versionMatch.Groups[1].Value
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$releaseExe = Join-Path $releaseDirectory 'kanyingyin.exe'

if (-not $SkipBuild) {
  if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable was not found: $FlutterPath"
  }
  $arguments = @('build', 'windows', '--release', '--no-pub') + $BuildArguments
  & $FlutterPath @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Windows Release build failed with exit code $LASTEXITCODE"
  }
}

if (-not (Test-Path -LiteralPath $releaseExe -PathType Leaf)) {
  throw "Windows Release executable was not found: $releaseExe"
}
$releaseVersion = (Get-Item -LiteralPath $releaseExe).VersionInfo.ProductVersion
if ([string]::IsNullOrWhiteSpace($releaseVersion) -or
    -not $releaseVersion.StartsWith($version, [System.StringComparison]::Ordinal)) {
  throw "Release executable version $releaseVersion does not match $version"
}

$installerScript = Join-Path $PSScriptRoot 'installer\build_inno_setup.ps1'
$packageStartedAt = Get-Date
& $installerScript `
  -Version $version `
  -ReleaseDirectory $releaseDirectory `
  -DesktopDirectory $DesktopDirectory

$installerCandidates = @(Get-ChildItem -LiteralPath $DesktopDirectory -Filter "*$version*.exe" -File | Where-Object {
  $_.LastWriteTime -ge $packageStartedAt.AddMinutes(-1) -and
  $_.VersionInfo.ProductVersion.StartsWith($version, [System.StringComparison]::Ordinal)
})
if ($installerCandidates.Count -ne 1) {
  throw "Expected exactly one EXE installer for $version, found $($installerCandidates.Count)"
}
$installer = $installerCandidates[0]
$hash = Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
$signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
[PSCustomObject]@{
  Version = $version
  ReleaseExecutable = $releaseExe
  ReleaseProductVersion = $releaseVersion
  Installer = $installer.FullName
  InstallerLength = $installer.Length
  InstallerProductVersion = $installer.VersionInfo.ProductVersion
  SHA256 = $hash.Hash
  SignatureStatus = $signature.Status
}
