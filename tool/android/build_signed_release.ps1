[CmdletBinding()]
param(
    [switch]$VersionOnly,
    [string]$VersionFixturePath,
    [ValidateSet('mobile', 'tvTest')]
    [string]$Flavor = 'mobile',
    [switch]$ApkOnly,
    [string[]]$DartDefines = @()
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 > $null

function Get-PubspecVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $versionLines = @($lines | Where-Object { $_ -match '^version:' })
    if ($versionLines.Count -ne 1) {
        throw 'pubspec.yaml must contain exactly one version field'
    }
    $versionMatch = [regex]::Match(
        $versionLines[0],
        '^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$'
    )
    if (-not $versionMatch.Success) {
        throw 'pubspec.yaml version must use x.y.z+build format'
    }
    $versionCode = 0
    $validVersionCode = [int]::TryParse(
        $versionMatch.Groups[2].Value,
        [ref]$versionCode
    )
    if (-not $validVersionCode -or $versionCode -gt 2100000000) {
        throw 'pubspec.yaml build number exceeds the Android versionCode limit'
    }
    return [PSCustomObject]@{
        Name = $versionMatch.Groups[1].Value
        Code = $versionCode
    }
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flutter = 'D:\flutter\bin\flutter.bat'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
if (-not [string]::IsNullOrWhiteSpace($VersionFixturePath)) {
    if (-not $VersionOnly) {
        throw 'VersionFixturePath is only available with VersionOnly'
    }
    $pubspecPath = $VersionFixturePath
}
$pubspecVersion = Get-PubspecVersion -Path $pubspecPath
if ($VersionOnly) {
    Write-Output "$($pubspecVersion.Name)+$($pubspecVersion.Code)"
    return
}
if ($pubspecVersion.Name -ne '1.0.10' -or $pubspecVersion.Code -ne 10010) {
    throw 'pubspec.yaml must use Windows formal version 1.0.10+10010'
}
$androidVersion = '1.0.6'
$androidVersionCode = 10006
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

    $expectedPackage = if ($Flavor -eq 'tvTest') {
        'com.kanyingyin.player.tvtest'
    } else {
        'com.kanyingyin.player'
    }
    $dartDefineArguments = @()
    foreach ($define in $DartDefines) {
        if ([string]::IsNullOrWhiteSpace($define)) {
            throw 'Dart defines cannot contain empty values'
        }
        $dartDefineArguments += '--dart-define'
        $dartDefineArguments += $define
    }

    Push-Location $projectRoot
    try {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $apkBuildArguments = @(
                'build', 'apk', '--release', '--flavor', $Flavor, '--no-pub'
            ) + $dartDefineArguments
            $apkBuildOutput = & $flutter @apkBuildArguments 2>&1
            $apkBuildExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorAction
        }
        $apkBuildOutput | ForEach-Object { $_.ToString() } | Write-Output
        if ($apkBuildExitCode -ne 0) { throw 'Android APK release build failed' }
        if (-not $ApkOnly) {
            $previousErrorAction = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $aabBuildArguments = @(
                    'build', 'appbundle', '--release', '--flavor', $Flavor, '--no-pub'
                ) + $dartDefineArguments
                $aabBuildOutput = & $flutter @aabBuildArguments 2>&1
                $aabBuildExitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $previousErrorAction
            }
            $aabBuildOutput | ForEach-Object { $_.ToString() } | Write-Output
            if ($aabBuildExitCode -ne 0) { throw 'Android AAB release build failed' }
        }
    }
    finally {
        Pop-Location
    }

    $apk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-$Flavor-release.apk"
    $aab = Join-Path $projectRoot "build\app\outputs\bundle\${Flavor}Release\app-$Flavor-release.aab"
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Release APK was not generated' }
    if (-not $ApkOnly -and -not (Test-Path -LiteralPath $aab -PathType Leaf)) {
        throw 'Release AAB was not generated'
    }

    $fullBundleVerifier = Join-Path $PSScriptRoot 'verify_full_media_bundle.ps1'
    & $fullBundleVerifier -PackagePath $apk -PackageKind 'apk'
    if (-not $ApkOnly) {
        & $fullBundleVerifier -PackagePath $aab -PackageKind 'aab'
    }

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

    if (-not $ApkOnly) {
        $aabVerification = & $jarsigner -verify -strict -keystore $keystore `
            -storepass:env KANYINGYIN_ANDROID_STORE_PASSWORD $aab 2>&1
        $aabVerificationCode = $LASTEXITCODE
        if ($aabVerificationCode -ne 0) {
            $aabVerification | Write-Output
            throw 'AAB signature verification failed'
        }
        Write-Output 'AAB signature verification passed'
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $appName = -join ([char]0x770B, [char]0x5F71, [char]0x97F3)
    $artifactSuffix = if ($Flavor -eq 'tvTest') {
        -join ([char]0x2D, [char]0x54, [char]0x56, [char]0x6D4B, [char]0x8BD5, [char]0x7248)
    } else {
        ''
    }
    $apkTarget = Join-Path $desktop "$appName-$androidVersion$artifactSuffix.apk"
    Copy-Item -LiteralPath $apk -Destination $apkTarget -Force
    if (-not $ApkOnly) {
        $aabTarget = Join-Path $desktop "$appName-$androidVersion$artifactSuffix.aab"
        Copy-Item -LiteralPath $aab -Destination $aabTarget -Force
        Write-Output "Android release verified: $apkTarget / $aabTarget"
    } else {
        Write-Output "Android APK release verified: $apkTarget"
    }
}
finally {
    foreach ($name in $requiredVariables) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    Remove-Variable keystore -ErrorAction SilentlyContinue
}
