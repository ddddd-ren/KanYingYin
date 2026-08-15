[CmdletBinding()]
param(
  [string]$TargetPath,
  [string]$SourcePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$expectedHash = '751EE5E79481626A428C1241DC7F94BCA2739B32588E669715BC5FB54D8FB8A2'
$downloadUrl = 'https://dist.nuget.org/win-x86-commandline/v7.6.0/nuget.exe'
if ([string]::IsNullOrWhiteSpace($TargetPath)) {
  $TargetPath = Join-Path $projectRoot 'build\tools\nuget.exe'
}
$target = [System.IO.Path]::GetFullPath($TargetPath)
$targetDirectory = Split-Path -Parent $target
$temporaryPath = "$target.download"

New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
try {
  $candidate = $target
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
      Invoke-WebRequest -Uri $downloadUrl -OutFile $temporaryPath -UseBasicParsing
    } else {
      Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath
    }
    $candidate = $temporaryPath
  }

  $actualHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
  if ($actualHash -ne $expectedHash) {
    throw "NuGet SHA-256 verification failed: $actualHash"
  }
  $signature = Get-AuthenticodeSignature -LiteralPath $candidate
  if ($signature.Status -ne 'Valid' -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '^CN=Microsoft Corporation(?:,|$)') {
    throw 'NuGet Microsoft Authenticode signature verification failed'
  }

  if ($candidate -eq $temporaryPath) {
    Move-Item -LiteralPath $temporaryPath -Destination $target -Force
  }
  Write-Output $target
} finally {
  if (Test-Path -LiteralPath $temporaryPath) {
    Remove-Item -LiteralPath $temporaryPath -Force
  }
}
