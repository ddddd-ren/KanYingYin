[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 > $null

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flutter = 'D:\flutter\bin\flutter.bat'
$androidVersion = '2.1.101'
$androidVersionCode = 20101
$requiredVariables = @(
    'KANYINGYIN_ANDROID_KEYSTORE',
    'KANYINGYIN_ANDROID_STORE_PASSWORD',
    'KANYINGYIN_ANDROID_KEY_ALIAS',
    'KANYINGYIN_ANDROID_KEY_PASSWORD'
)

try {
    foreach ($name in $requiredVariables) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = [Environment]::GetEnvironmentVariable($name, 'User')
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Missing Android signing environment variable: $name"
        }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }

    $keystore = [Environment]::GetEnvironmentVariable(
        'KANYINGYIN_ANDROID_KEYSTORE',
        'Process'
    )
    if (-not (Test-Path -LiteralPath $keystore -PathType Leaf)) {
        throw 'Android signing keystore does not exist'
    }
    if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
        throw 'D:\flutter 3.41.9 was not found'
    }

    $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Encoding UTF8
    $versionLine = $pubspec | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    if ($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
        throw 'Unable to read Android version from pubspec.yaml'
    }
    $windowsVersion = $Matches[1]
    $windowsBuildNumber = $Matches[2]
    if ($windowsVersion -ne '2.1.101' -or $windowsBuildNumber -ne '20101') {
        throw "Windows pubspec 版本必须为 2.1.101+20101，实际为 $windowsVersion+$windowsBuildNumber"
    }
    $expectedPackage = 'com.kanyingyin.player'

    Push-Location $projectRoot
    try {
        & $flutter build apk --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Android APK release build failed' }
        & $flutter build appbundle --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Android AAB release build failed' }
    }
    finally {
        Pop-Location
    }

    $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
    $aab = Join-Path $projectRoot 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Release APK was not generated' }
    if (-not (Test-Path -LiteralPath $aab -PathType Leaf)) { throw 'Release AAB was not generated' }

    $fullBundleVerifier = Join-Path $PSScriptRoot 'verify_full_media_bundle.ps1'
    & $fullBundleVerifier -PackagePath $apk -PackageKind 'apk'
    & $fullBundleVerifier -PackagePath $aab -PackageKind 'aab'

    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -eq $buildTools) { throw 'Android build-tools were not found' }
    $apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $jarsigner = Join-Path $env:JAVA_HOME 'bin\jarsigner.exe'
    if (-not (Test-Path -LiteralPath $jarsigner)) {
        $jarsigner = 'C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot\bin\jarsigner.exe'
    }

    & $apksigner verify --verbose --print-certs $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
    $badging = & $aapt dump badging $apk
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read APK manifest' }
    $packageLine = $badging | Where-Object { $_ -match '^package:' } | Select-Object -First 1
    if ($packageLine -notmatch "name='$([regex]::Escape($expectedPackage))'") {
        throw 'APK applicationId is incorrect'
    }
    if ($packageLine -notmatch "versionCode='$androidVersionCode'") {
        throw 'APK versionCode is incorrect'
    }
    if ($packageLine -notmatch "versionName='$([regex]::Escape($androidVersion))'") {
        throw 'APK versionName is incorrect'
    }

    $aabVerification = & $jarsigner -verify -strict -keystore $keystore `
        -storepass:env KANYINGYIN_ANDROID_STORE_PASSWORD $aab 2>&1
    $aabVerificationCode = $LASTEXITCODE
    if ($aabVerificationCode -ne 0) {
        $aabVerification | Write-Output
        throw 'AAB signature verification failed'
    }
    Write-Output 'AAB signature verification passed'

    $desktop = [Environment]::GetFolderPath('Desktop')
    $appName = -join ([char]0x770B, [char]0x5F71, [char]0x97F3)
    $apkTarget = Join-Path $desktop "$appName-$androidVersion.apk"
    $aabTarget = Join-Path $desktop "$appName-$androidVersion.aab"
    Copy-Item -LiteralPath $apk -Destination $apkTarget -Force
    Copy-Item -LiteralPath $aab -Destination $aabTarget -Force
    Write-Output "Android release verified: $apkTarget / $aabTarget"
}
finally {
    foreach ($name in $requiredVariables) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    Remove-Variable keystore -ErrorAction SilentlyContinue
}
