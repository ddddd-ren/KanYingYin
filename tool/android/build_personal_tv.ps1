[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigurationPath,
    [Parameter(Mandatory)]
    [string]$MetadataPath,
    [string]$DesktopDirectory = (Join-Path $env:USERPROFILE 'Desktop')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
chcp 65001 > $null

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$assetDirectory = Join-Path $projectRoot 'assets\tv_preload'
$manifestPath = Join-Path $assetDirectory 'manifest.json'
$configurationAsset = Join-Path $assetDirectory 'configuration.kyyconfig'
$metadataAsset = Join-Path $assetDirectory 'metadata.kyymeta'
$validator = Join-Path $projectRoot 'tool\tv_preload\validate_and_write_manifest.dart'
$releaseScript = Join-Path $PSScriptRoot 'build_signed_release.ps1'
$dart = 'D:\flutter\bin\dart.bat'
$password = [Environment]::GetEnvironmentVariable('KYY_CONFIG_PASSWORD', 'Process')

if ([string]::IsNullOrWhiteSpace($password)) {
    throw 'Missing KYY_CONFIG_PASSWORD process environment variable'
}
if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf) -or
    -not $ConfigurationPath.EndsWith('.kyyconfig', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Configuration input must be an existing .kyyconfig file'
}
if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf) -or
    -not $MetadataPath.EndsWith('.kyymeta', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Metadata input must be an existing .kyymeta file'
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Tracked disabled TV preload manifest was not found'
}
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw 'TV preload validator was not found'
}
if (-not (Test-Path -LiteralPath $dart -PathType Leaf)) {
    throw 'D:\flutter 3.41.9 was not found'
}

$manifestBackup = [System.IO.File]::ReadAllBytes($manifestPath)
$dartDefines = @()
try {
    Copy-Item -LiteralPath $ConfigurationPath -Destination $configurationAsset -Force
    Copy-Item -LiteralPath $MetadataPath -Destination $metadataAsset -Force

    Push-Location $projectRoot
    try {
        & $dart run $validator `
            --configuration $configurationAsset `
            --metadata $metadataAsset `
            --manifest $manifestPath
        if ($LASTEXITCODE -ne 0) {
            throw 'TV preload input validation failed'
        }
    }
    finally {
        Pop-Location
    }

    $dartDefines = @('KYY_TV_PRELOAD_PASSWORD=' + $password)
    & $releaseScript -Flavor tvTest -ApkOnly -DartDefines $dartDefines
    if ($LASTEXITCODE -ne 0) {
        throw 'Personal Android TV APK build failed'
    }

    $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw -Encoding UTF8
    $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$')
    if (-not $versionMatch.Success) {
        throw 'Unable to read version from pubspec.yaml'
    }
    $version = $versionMatch.Groups[1].Value
    $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-tvTest-release.apk'
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
        throw 'Personal Android TV APK was not generated'
    }

    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $buildTools) {
        throw 'Android build-tools were not found'
    }
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $badging = & $aapt dump badging $apk
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to verify personal Android TV APK'
    }
    $badgingText = $badging -join "`n"
    if ($badgingText -notmatch 'leanback-launchable-activity:' -or
        $badgingText -notmatch "uses-feature-not-required:\s+name='android\.hardware\.touchscreen'") {
        throw 'Personal Android TV APK is missing TV compatibility declarations'
    }

    $appName = -join ([char]0x770B, [char]0x5F71, [char]0x97F3)
    $target = Join-Path $DesktopDirectory "$appName-$version-TV个人预置测试版.apk"
    Copy-Item -LiteralPath $apk -Destination $target -Force
    $targetItem = Get-Item -LiteralPath $target
    [PSCustomObject]@{
        Version = $version
        Path = $targetItem.FullName
        Length = $targetItem.Length
        SHA256 = (Get-FileHash -LiteralPath $targetItem.FullName -Algorithm SHA256).Hash
    }
}
finally {
    if (Test-Path -LiteralPath $configurationAsset -PathType Leaf) {
        Remove-Item -LiteralPath $configurationAsset -Force
    }
    if (Test-Path -LiteralPath $metadataAsset -PathType Leaf) {
        Remove-Item -LiteralPath $metadataAsset -Force
    }
    [System.IO.File]::WriteAllBytes($manifestPath, $manifestBackup)
    [Environment]::SetEnvironmentVariable('KYY_CONFIG_PASSWORD', $null, 'Process')
    [Environment]::SetEnvironmentVariable('KYY_TV_PRELOAD_PASSWORD', $null, 'Process')
    $password = $null
    $dartDefines = @()
}
