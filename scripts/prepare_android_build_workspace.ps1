# AOT gen_snapshot on this Windows SDK cannot read app.dill under a Chinese
# path. Build a fresh ASCII source mirror; never delete/move the real project.
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $ProjectRoot 'android-env.ps1')
$workspace = Join-Path $androidToolRoot ('horizon-builds/' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + $PID)
if ($workspace -match '[^\x00-\x7F]') { throw 'Android AOT build workspace must use an ASCII path.' }
New-Item -ItemType Directory -Path $workspace | Out-Null
$source = Join-Path $ProjectRoot 'flutter_app'
foreach ($name in @('lib','assets','android')) {
    $target = Join-Path $workspace $name
    & robocopy (Join-Path $source $name) $target /E /NFL /NDL /NJH /NJS /NP /XD build .gradle .cxx /XF local.properties key.properties *.jks *.keystore | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Failed to copy Android build sources: $name" }
}
foreach ($name in @('pubspec.yaml','pubspec.lock','analysis_options.yaml','.metadata')) {
    $file = Join-Path $source $name
    if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $workspace $name) }
}
# The SDK mirror is on C: while the existing Pub cache is on D:. Kotlin's
# incremental path relativizer cannot cross volume roots. Scope this workaround
# to the disposable mirror; keep the user's project/global Gradle settings.
Add-Content -LiteralPath (Join-Path $workspace 'android/gradle.properties') -Value "`nkotlin.incremental=false"
# Recreate package configuration for the mirror using existing pinned packages.
Push-Location $workspace
try {
    & (Join-Path $ProjectRoot 'flutter.ps1') -FlutterArguments @('pub','get','--offline') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Offline dependency resolution failed. No new installation was attempted.' }
} finally { Pop-Location }
if ((Get-FileHash -LiteralPath (Join-Path $source 'pubspec.lock')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $workspace 'pubspec.lock')).Hash) { throw 'Offline resolution changed the pinned lockfile; stop and inspect.' }
$global:LASTEXITCODE = 0
Write-Output $workspace
