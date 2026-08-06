[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'build_signed_release.ps1'
& $script -Flavor tvTest -ApkOnly
if ($LASTEXITCODE -ne 0) {
    throw 'Android TV test APK build failed'
}
