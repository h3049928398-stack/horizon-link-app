$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fontManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'font_sources.json') -Raw | ConvertFrom-Json
$fontCache = Join-Path $projectRoot '.tools/font-sources'
New-Item -ItemType Directory -Path $fontCache -Force | Out-Null
foreach ($fontEntry in $fontManifest.files) {
    $fontTarget = Join-Path $fontCache $fontEntry.file
    if ((Test-Path -LiteralPath $fontTarget) -and ((Get-FileHash -LiteralPath $fontTarget -Algorithm SHA256).Hash -eq $fontEntry.sha256)) { continue }
    $fontTemporary = "$fontTarget.download"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/google/fonts/$($fontManifest.revision)/$($fontEntry.path)" -OutFile $fontTemporary
    if ((Get-FileHash -LiteralPath $fontTemporary -Algorithm SHA256).Hash -ne $fontEntry.sha256) { throw "Font source checksum mismatch: $($fontEntry.file)" }
    Move-Item -LiteralPath $fontTemporary -Destination $fontTarget -Force
}
Write-Host 'Verified official OFL font sources. Run python scripts/prepare_flutter_fonts.py to build offline.'
