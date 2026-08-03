[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('apk', 'aab')]
  [string]$PackageKind,

  [Parameter(Mandatory = $true)]
  [string]$PackagePath,

  [string]$NativeCacheRoot = ''
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($NativeCacheRoot)) {
  $NativeCacheRoot = Join-Path $projectRoot `
    'build\media_kit_libs_android_video\v1.1.11'
}

function Get-ZipEntrySha256 {
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$EntryName
  )

  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $archive.GetEntry($EntryName)
    if ($null -eq $entry) {
      throw "压缩包缺少条目：$ZipPath -> $EntryName"
    }
    $stream = $entry.Open()
    try {
      $sha256 = [System.Security.Cryptography.SHA256]::Create()
      try {
        $hash = $sha256.ComputeHash($stream)
      } finally {
        $sha256.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  } finally {
    $archive.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

$definitions = [ordered]@{
  'arm64-v8a' = [ordered]@{
    Jar = 'full-arm64-v8a.jar'
    Sha256 = 'cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd'
  }
  'armeabi-v7a' = [ordered]@{
    Jar = 'full-armeabi-v7a.jar'
    Sha256 = 'b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec'
  }
  'x86' = [ordered]@{
    Jar = 'full-x86.jar'
    Sha256 = '8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901'
  }
  'x86_64' = [ordered]@{
    Jar = 'full-x86_64.jar'
    Sha256 = '848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d'
  }
}
$packageAbis = @(
  'arm64-v8a',
  'armeabi-v7a',
  'x86_64'
)

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$packagePrefix = if ($PackageKind -eq 'aab') { 'base/lib' } else { 'lib' }

foreach ($abi in $definitions.Keys) {
  $definition = $definitions[$abi]
  $jarPath = Join-Path $NativeCacheRoot $definition.Jar
  if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf)) {
    throw "缺少 Full 原生 JAR：$jarPath"
  }
  $jarFileHash = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash
  if ($jarFileHash.ToLowerInvariant() -ne $definition.Sha256) {
    throw "Full 原生 JAR 哈希错误：$jarPath"
  }
}

foreach ($abi in $packageAbis) {
  $definition = $definitions[$abi]
  $jarPath = Join-Path $NativeCacheRoot $definition.Jar
  $jarEntry = "lib/$abi/libmpv.so"
  $packageEntry = "$packagePrefix/$abi/libmpv.so"
  $jarLibHash = Get-ZipEntrySha256 -ZipPath $jarPath -EntryName $jarEntry
  $packageLibHash = Get-ZipEntrySha256 `
    -ZipPath $resolvedPackage `
    -EntryName $packageEntry
  if ($jarLibHash -ne $packageLibHash) {
    throw "安装包中的 $abi/libmpv.so 不是固定 Full 资产"
  }
  Write-Output "Full libmpv verified: $PackageKind / $abi / $packageLibHash"
}
