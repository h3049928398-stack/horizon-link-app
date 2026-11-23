$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
function Test-HorizonCache {
    try {
        $request = [System.Net.WebRequest]::Create('http://127.0.0.1:18765/health')
        $request.Proxy = $null
        $request.Timeout = 1000
        $response = $request.GetResponse()
        try {
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try { return $reader.ReadToEnd() -eq 'horizon-official-maven-cache-v1' }
            finally { $reader.Dispose() }
        } finally { $response.Dispose() }
    } catch { return $false }
}
if (Test-HorizonCache) { return }
$cacheScript = Join-Path $PSScriptRoot 'official_maven_cache.py'
$logDirectory = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$cacheProcess = Start-Process -FilePath (Get-Command python.exe).Source -ArgumentList @('-u', ('"' + $cacheScript + '"')) -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDirectory "android-maven-$stamp.log") -RedirectStandardError (Join-Path $logDirectory "android-maven-$stamp-error.log") -PassThru
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if (Test-HorizonCache) { return }
    if ($cacheProcess.HasExited) { throw 'Official dependency cache failed to start. Check artifacts/android-maven-*.log.' }
    Start-Sleep -Milliseconds 250
}
throw 'Official dependency cache did not become ready on 127.0.0.1:18765.'
