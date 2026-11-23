# Download only from the official Android repository, then verify before extraction.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $downloadProxyArgs = @()
    $systemProxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($systemProxy.ProxyEnable -eq 1 -and $systemProxy.ProxyServer -match '^(127\.0\.0\.1|localhost):\d+$') {
        $downloadProxyArgs = @('--proxy', ('http://' + $systemProxy.ProxyServer))
    }
    $manifestPath = '.tools\downloads\android-repository.xml'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        & curl.exe @downloadProxyArgs --fail --location --silent --show-error --retry 3 --retry-all-errors --connect-timeout 10 --max-time 60 --output $manifestPath 'https://dl.google.com/android/repository/repository2-3.xml'
        if ($LASTEXITCODE -ne 0) { throw 'Official SDK repository download failed.' }
    }
    [xml]$repository = Get-Content -LiteralPath $manifestPath -Raw
    $requiredPackages = @('platforms;android-35','platforms;android-36','build-tools;36.0.0','ndk;28.2.13676358','cmake;3.22.1')
    foreach ($packageId in $requiredPackages) {
        $package = @($repository.DocumentElement.remotePackage | Where-Object path -eq $packageId)[0]
        $archive = @($package.archives.archive | Where-Object { -not $_.'host-os' -or $_.'host-os' -eq 'windows' })[0].complete
        if (-not $archive) { throw "Missing official package: $packageId" }
        $archivePath = Join-Path '.tools\downloads' $archive.url
        $expectedHash = $archive.checksum.InnerText.Trim().ToLower()
        $expectedSize = [long]$archive.size
        $verified = $false
        if ((Test-Path -LiteralPath $archivePath) -and (Get-Item -LiteralPath $archivePath).Length -eq $expectedSize) {
            $verified = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA1).Hash.ToLower() -eq $expectedHash
        }
        if (-not $verified) {
            Write-Host "Downloading official $packageId"
            & curl.exe @downloadProxyArgs --fail --location --silent --show-error --http1.1 --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 10 --max-time 300 --output $archivePath --write-out '%{size_download} bytes downloaded' ('https://dl.google.com/android/repository/' + $archive.url)
            if ($LASTEXITCODE -ne 0) { throw "Download failed: $packageId" }
        }
        if ((Get-Item -LiteralPath $archivePath).Length -ne $expectedSize) { throw "Size mismatch: $packageId" }
        if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA1).Hash.ToLower() -ne $expectedHash) { throw "Checksum mismatch: $packageId" }
        Write-Host "Verified $packageId"
    }
    & python scripts/install_android_packages.py --offline
    if ($LASTEXITCODE -ne 0) { throw 'SDK extraction failed.' }
} finally { Pop-Location }
