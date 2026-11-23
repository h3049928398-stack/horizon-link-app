param(
    [string]$MetadataPath = '.tools/release/public-metadata.json',
    [ValidateSet('apk','appbundle')][string]$Format = 'apk',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not [IO.Path]::IsPathRooted($MetadataPath)) { $MetadataPath = Join-Path $projectRoot $MetadataPath }
$defines = Join-Path $projectRoot 'artifacts/release-prep/release-defines.json'
& python (Join-Path $PSScriptRoot 'release_preflight.py') --metadata $MetadataPath --weekly (Join-Path $projectRoot 'config/weekly-content.json') --output $defines
if ($LASTEXITCODE -ne 0) { throw 'Release public metadata is incomplete. No build started.' }
foreach ($name in @('HL_KEYSTORE','HL_STORE_PASSWORD','HL_KEY_ALIAS','HL_KEY_PASSWORD')) {
    if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Missing private signing environment variable: $name" }
}
if (-not [IO.Path]::IsPathRooted($env:HL_KEYSTORE) -or -not (Test-Path -LiteralPath $env:HL_KEYSTORE -PathType Leaf)) { throw 'HL_KEYSTORE must be an existing absolute path.' }
if ($CheckOnly) { Write-Host 'Preflight passed. No build, installation or publication performed.'; exit 0 }
$buildRoot = & (Join-Path $PSScriptRoot 'prepare_android_build_workspace.ps1') -ProjectRoot $projectRoot
Push-Location $buildRoot
try {
    & (Join-Path $projectRoot 'flutter.ps1') -FlutterArguments @('build',$Format,'--release','--no-pub',"--dart-define-from-file=$defines")
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
} finally { Pop-Location }
. (Join-Path $projectRoot 'android-env.ps1')
$stagingDirectory = Join-Path $androidToolRoot 'horizon-artifacts'
New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
if ($Format -eq 'apk') {
    $source = Join-Path $buildRoot 'build/app/outputs/flutter-apk/app-release.apk'
    $destination = Join-Path $stagingDirectory 'horizon-link-release.apk'
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $certificate = & (Join-Path $env:ANDROID_HOME 'build-tools/36.0.0/apksigner.bat') verify --verbose --print-certs $destination
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    if (($certificate -join "`n") -match 'CN=Android Debug') { throw 'Debug certificate detected. Not a production release.' }
    $certificate | Set-Content -LiteralPath (Join-Path $projectRoot 'artifacts/release-prep/signing-certificate.txt')
} else {
    $source = Join-Path $buildRoot 'build/app/outputs/bundle/release/app-release.aab'
    $destination = Join-Path $stagingDirectory 'horizon-link-release.aab'
    Copy-Item -LiteralPath $source -Destination $destination -Force
    & (Join-Path $env:JAVA_HOME 'bin/jarsigner.exe') -verify $destination
    if ($LASTEXITCODE -ne 0) { throw 'AAB signature verification failed.' }
}
Get-FileHash -LiteralPath $destination -Algorithm SHA256 | Format-List
Write-Host "Built and staged: $destination. No installation or store upload performed."
