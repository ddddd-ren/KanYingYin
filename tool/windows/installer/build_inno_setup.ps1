[CmdletBinding()]
param(
  [string]$Version = '2.1.135',
  [string]$ReleaseDirectory,
  [string]$DesktopDirectory = (Join-Path $env:USERPROFILE 'Desktop'),
  [string]$IsccPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
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

& $IsccPath "/DMyAppVersion=$Version" "/DBuildDir=$releasePath" `
  "/DOutputDir=$desktopPath" $scriptPath
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

$installer = Get-ChildItem -LiteralPath $desktopPath -Filter '*.exe' -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $installer) {
  throw "Generated installer was not found in $desktopPath"
}
$hash = Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
$signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
[PSCustomObject]@{
  Path = $installer.FullName
  SHA256 = $hash.Hash
  SignatureStatus = $signature.Status
}
