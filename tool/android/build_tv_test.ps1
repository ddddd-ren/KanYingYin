[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 > $null

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $PSScriptRoot 'build_signed_release.ps1'
$privateOutput = Join-Path $PSScriptRoot 'private-output'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $privateOutput -Force | Out-Null

$buildLog = Join-Path $privateOutput "tv-test-$timestamp-build.log"
& $script -Flavor tvTest -ApkOnly 2>&1 |
    Tee-Object -FilePath $buildLog
if ($LASTEXITCODE -ne 0) {
    throw 'Android TV test APK build failed'
}

$apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-tvTest-release.apk'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
    throw 'Android TV test APK was not generated'
}

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if ($null -eq $buildTools) {
    throw 'Android build-tools were not found'
}
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'

$badging = & $aapt dump badging $apk 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read Android TV APK badging'
}
$badgingPath = Join-Path $privateOutput "tv-test-$timestamp-aapt-badging.txt"
$badging | Set-Content -LiteralPath $badgingPath -Encoding UTF8
$badgingText = $badging -join "`n"
$touchscreenFeature = 'android.hardware.touchscreen'
if ($badgingText -notmatch "package: name='com\.kanyingyin\.player\.tvtest'") {
    throw 'Android TV APK package name is incorrect'
}
if ($badgingText -notmatch 'leanback-launchable-activity:') {
    throw 'Android TV APK does not expose a Leanback launcher activity'
}
if ($badgingText -notmatch "uses-feature-not-required:\s+name='$([regex]::Escape($touchscreenFeature))'") {
    throw 'Android TV APK incorrectly requires a touchscreen'
}

$manifest = & $aapt dump xmltree $apk AndroidManifest.xml 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read Android TV APK manifest'
}
$manifestPath = Join-Path $privateOutput "tv-test-$timestamp-manifest.txt"
$manifest | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$manifestText = $manifest -join "`n"
if ($manifestText -notmatch 'android\.intent\.category\.LEANBACK_LAUNCHER') {
    throw 'Android TV APK manifest is missing LEANBACK_LAUNCHER'
}
if ($manifestText -notmatch 'android:banner') {
    throw 'Android TV APK manifest is missing android:banner'
}

$signature = & $apksigner verify --verbose --print-certs $apk 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Android TV APK signature verification failed'
}
$signaturePath = Join-Path $privateOutput "tv-test-$timestamp-signature.txt"
$signature | Set-Content -LiteralPath $signaturePath -Encoding UTF8

$fullBundleVerifier = Join-Path $PSScriptRoot 'verify_full_media_bundle.ps1'
$fullBundle = & $fullBundleVerifier -PackagePath $apk -PackageKind apk 2>&1
$fullBundlePath = Join-Path $privateOutput "tv-test-$timestamp-full-bundle.txt"
$fullBundle | Set-Content -LiteralPath $fullBundlePath -Encoding UTF8

$apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$summary = [ordered]@{
    packagePath = (Resolve-Path -LiteralPath $apk).Path
    packageName = 'com.kanyingyin.player.tvtest'
    sha256 = $apkHash
    buildTools = $buildTools.Name
    buildLog = $buildLog
    badging = $badgingPath
    manifest = $manifestPath
    signature = $signaturePath
    fullBundle = $fullBundlePath
}
$summaryPath = Join-Path $privateOutput "tv-test-$timestamp-summary.json"
$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Output "Android TV APK independently verified: $apk"
Write-Output "SHA256: $apkHash"
Write-Output "Verification summary: $summaryPath"
