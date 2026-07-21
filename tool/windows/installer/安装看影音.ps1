[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$msixFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Filter '看影音-*.msix' -File)
if ($msixFiles.Count -ne 1) {
  throw '安装目录必须且只能包含一个看影音 MSIX 安装包'
}
$msixPath = $msixFiles[0].FullName
$cerPath = Join-Path $scriptRoot '看影音.cer'
$hashPath = Join-Path $scriptRoot 'SHA256.txt'
if (-not (Test-Path -LiteralPath $cerPath -PathType Leaf)) {
  throw '缺少看影音公钥证书'
}
if (-not (Test-Path -LiteralPath $hashPath -PathType Leaf)) {
  throw '缺少 SHA256 校验文件'
}

$hashLine = (Get-Content -LiteralPath $hashPath -Encoding UTF8 | Select-Object -First 1).Trim()
if ($hashLine -notmatch '^([A-Fa-f0-9]{64})\s+(.+\.msix)$') {
  throw 'SHA256 校验文件格式无效'
}
$expectedHash = $Matches[1].ToUpperInvariant()
if ($Matches[2] -ne $msixFiles[0].Name) {
  throw 'SHA256 校验文件中的安装包名称不匹配'
}
$actualHash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
  throw 'MSIX 哈希校验失败'
}

if ($msixFiles[0].BaseName -notmatch '^看影音-(\d+\.\d+\.\d+)$') {
  throw 'MSIX 文件名中的版本无效'
}
$expectedVersion = "$($Matches[1]).0"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Xml.Linq
$archive = [System.IO.Compression.ZipFile]::OpenRead($msixPath)
try {
  $manifestEntry = $archive.Entries |
    Where-Object { $_.FullName -eq 'AppxManifest.xml' } |
    Select-Object -First 1
  if ($null -eq $manifestEntry) {
    throw 'MSIX 中缺少 AppxManifest.xml'
  }
  $stream = $manifestEntry.Open()
  try {
    $manifest = [System.Xml.Linq.XDocument]::Load($stream)
  } finally {
    $stream.Dispose()
  }
} finally {
  $archive.Dispose()
}

$identity = $manifest.Root.Elements() |
  Where-Object { $_.Name.LocalName -eq 'Identity' } |
  Select-Object -First 1
if ($null -eq $identity) {
  throw 'MSIX 清单缺少 Identity'
}
$name = $identity.Attribute('Name').Value
$publisher = $identity.Attribute('Publisher').Value
$version = $identity.Attribute('Version').Value
$architecture = $identity.Attribute('ProcessorArchitecture').Value
if ($name -ne 'com.kanyingyin.player') { throw 'MSIX 包标识不匹配' }
if ($publisher -ne 'CN=KanYingYin') { throw 'MSIX 发布者不匹配' }
if ($version -ne $expectedVersion) { throw 'MSIX 清单版本与文件名不匹配' }
if ($architecture -ne 'x64') { throw 'MSIX 不是 x64 安装包' }

$signature = Get-AuthenticodeSignature -LiteralPath $msixPath
$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cerPath)
if ($null -eq $signature.SignerCertificate) {
  throw 'MSIX 没有数字签名'
}
if ($signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
  throw 'MSIX 签名证书与安装包证书不一致'
}

Import-Certificate -FilePath $cerPath `
  -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null

if ((Get-AuthenticodeSignature -LiteralPath $msixPath).Status -ne 'Valid') {
  throw 'MSIX 签名验证失败'
}

Add-AppxPackage -Path $msixPath
Write-Host '看影音安装完成。'
