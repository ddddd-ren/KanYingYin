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
$cleanupHelper = Join-Path $PSScriptRoot 'clear_personal_tv_build_residue.ps1'
$dart = 'D:\flutter\bin\dart.bat'
$password = $null
$manifestBackup = $null
$dartDefines = @()
$configurationCopied = $false
$metadataCopied = $false

function Invoke-PersonalTvCleanupStep {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        Write-Warning "Personal TV cleanup failed ($Name): $($_.Exception.Message)"
    }
}

try {
    if (-not (Test-Path -LiteralPath $cleanupHelper -PathType Leaf)) {
        throw 'Personal TV build residue cleanup helper was not found'
    }
    . $cleanupHelper

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
    Copy-Item -LiteralPath $ConfigurationPath -Destination $configurationAsset -Force
    $configurationCopied = $true
    Copy-Item -LiteralPath $MetadataPath -Destination $metadataAsset -Force
    $metadataCopied = $true

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
    $personalEditionLabel = 'TV' + (-join @(
        [char]0x4E2A,
        [char]0x4EBA,
        [char]0x9884,
        [char]0x7F6E,
        [char]0x6D4B,
        [char]0x8BD5,
        [char]0x7248
    ))
    $target = Join-Path $DesktopDirectory "$appName-$version-$personalEditionLabel.apk"
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
    Invoke-PersonalTvCleanupStep -Name 'configuration asset' -Action {
        if ($configurationCopied -and
            (Test-Path -LiteralPath $configurationAsset -PathType Leaf)) {
            Remove-Item -LiteralPath $configurationAsset -Force
        }
    }
    Invoke-PersonalTvCleanupStep -Name 'metadata asset' -Action {
        if ($metadataCopied -and
            (Test-Path -LiteralPath $metadataAsset -PathType Leaf)) {
            Remove-Item -LiteralPath $metadataAsset -Force
        }
    }
    Invoke-PersonalTvCleanupStep -Name 'manifest restore' -Action {
        if ($null -ne $manifestBackup) {
            [System.IO.File]::WriteAllBytes($manifestPath, $manifestBackup)
        }
    }
    Invoke-PersonalTvCleanupStep -Name 'intermediates residue' -Action {
        if (Get-Command Clear-PersonalTvBuildResidue -CommandType Function -ErrorAction SilentlyContinue) {
            Clear-PersonalTvBuildResidue -ProjectRoot $projectRoot
        }
    }
    Invoke-PersonalTvCleanupStep -Name 'configuration password' -Action {
        [Environment]::SetEnvironmentVariable('KYY_CONFIG_PASSWORD', $null, 'Process')
    }
    Invoke-PersonalTvCleanupStep -Name 'preload password' -Action {
        [Environment]::SetEnvironmentVariable('KYY_TV_PRELOAD_PASSWORD', $null, 'Process')
    }
    Invoke-PersonalTvCleanupStep -Name 'local secrets' -Action {
        $script:password = $null
        $script:dartDefines = @()
    }
}
