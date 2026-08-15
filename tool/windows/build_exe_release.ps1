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
$buildDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $projectRoot 'build\windows\x64')
)
$releaseDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $buildDirectory 'runner\Release')
)
$releaseExe = Join-Path $releaseDirectory 'kanyingyin.exe'
$releaseApp = Join-Path $releaseDirectory 'data\app.so'
$flutterApp = Join-Path $projectRoot 'build\windows\app.so'
$cmakeCachePath = Join-Path $buildDirectory 'CMakeCache.txt'

if (-not $SkipBuild) {
  if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable was not found: $FlutterPath"
  }
  if (-not $releaseDirectory.StartsWith(
      "$buildDirectory\",
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Refusing to clean Release outside project build directory: $releaseDirectory"
  }
  if (Test-Path -LiteralPath $releaseDirectory) {
    Remove-Item -LiteralPath $releaseDirectory -Recurse -Force
  }
  if (Test-Path -LiteralPath $releaseDirectory) {
    throw "Windows Release cleanup failed: $releaseDirectory"
  }
  if (Test-Path -LiteralPath $cmakeCachePath) {
    Remove-Item -LiteralPath $cmakeCachePath -Force
  }

  $nuGetScript = Join-Path $PSScriptRoot 'prepare_nuget.ps1'
  $nuGetPath = & $nuGetScript | Select-Object -Last 1
  $nuGetDirectory = Split-Path -Parent $nuGetPath
  $originalPath = $env:PATH
  $buildStartedAt = Get-Date
  $locationPushed = $false
  try {
    Push-Location -LiteralPath $projectRoot
    $locationPushed = $true
    $env:PATH = "$nuGetDirectory;$originalPath"
    $arguments = @('build', 'windows', '--release', '--no-pub') + $BuildArguments
    & $FlutterPath @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Windows Release build failed with exit code $LASTEXITCODE"
    }
  } finally {
    $env:PATH = $originalPath
    if ($locationPushed) {
      Pop-Location
    }
  }

  foreach ($releaseArtifact in @($releaseExe, $releaseApp)) {
    if (-not (Test-Path -LiteralPath $releaseArtifact -PathType Leaf)) {
      throw "Windows Release is missing current build artifact: $releaseArtifact"
    }
    $releaseInfo = Get-Item -LiteralPath $releaseArtifact
    if ($releaseInfo.Length -le 0) {
      throw "Windows Release artifact is empty: $releaseArtifact"
    }
  }
  if ((Get-Item -LiteralPath $releaseExe).LastWriteTime -lt
      $buildStartedAt.AddSeconds(-2)) {
    throw "Windows Release executable is not from the current build: $releaseExe"
  }
  if (-not (Test-Path -LiteralPath $flutterApp -PathType Leaf)) {
    throw "Windows Flutter build output does not exist: $flutterApp"
  }
  $flutterAppHash = (Get-FileHash -LiteralPath $flutterApp -Algorithm SHA256).Hash
  $releaseAppHash = (Get-FileHash -LiteralPath $releaseApp -Algorithm SHA256).Hash
  if ($flutterAppHash -ne $releaseAppHash) {
    throw 'Windows Release app.so does not match the current Flutter build output'
  }

  $cmakeCache = Get-Content -LiteralPath $cmakeCachePath -Raw -Encoding UTF8
  $nuGetCacheMatch = [regex]::Match($cmakeCache, '(?m)^NUGET:FILEPATH=(.+)$')
  if (-not $nuGetCacheMatch.Success -or
      [System.IO.Path]::GetFullPath($nuGetCacheMatch.Groups[1].Value.Trim()) -ne
      [System.IO.Path]::GetFullPath($nuGetPath)) {
    throw 'CMakeCache.txt does not use the verified NuGet inside this worktree'
  }
}

if (-not (Test-Path -LiteralPath $releaseExe -PathType Leaf)) {
  throw "Windows Release executable was not found: $releaseExe"
}
$releaseVersion = (Get-Item -LiteralPath $releaseExe).VersionInfo.ProductVersion
if ([string]::IsNullOrWhiteSpace($releaseVersion) -or
    $releaseVersion -ne $version) {
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
$releaseHash = Get-FileHash -LiteralPath $releaseExe -Algorithm SHA256
[PSCustomObject]@{
  Version = $version
  ReleaseExecutable = $releaseExe
  ReleaseProductVersion = $releaseVersion
  ReleaseSHA256 = $releaseHash.Hash
  Installer = $installer.FullName
  InstallerLength = $installer.Length
  InstallerProductVersion = $installer.VersionInfo.ProductVersion
  SHA256 = $hash.Hash
  SignatureStatus = $signature.Status
}
