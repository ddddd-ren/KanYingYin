function Clear-PersonalTvBuildResidue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $intermediatesRoot = [System.IO.Path]::GetFullPath(
        (Join-Path $ProjectRoot 'build\app\intermediates')
    )
    if (-not (Test-Path -LiteralPath $intermediatesRoot -PathType Container)) {
        return
    }
    $intermediatesRoot = (Resolve-Path -LiteralPath $intermediatesRoot).Path
    $intermediatesPrefix = $intermediatesRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $targets = @(
        Get-ChildItem -LiteralPath $intermediatesRoot -Directory -Recurse -Force |
            Where-Object { $_.Name -ceq 'tv_preload' }
    )
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.FullName -PathType Container)) {
            continue
        }
        $targetPath = [System.IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $target.FullName).Path
        )
        if (-not $targetPath.StartsWith(
                $intermediatesPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove TV preload residue outside intermediates: $targetPath"
        }
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }
}
