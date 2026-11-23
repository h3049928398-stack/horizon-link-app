# Persistent Windows HTTPS client. Certificate verification stays enabled.
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.Proxy = [System.Net.WebProxy]::new('http://127.0.0.1:7890')
$handler.UseProxy = $true
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(60)
try {
    while ($null -ne ($line = [Console]::ReadLine())) {
        try {
            $request = $line | ConvertFrom-Json
            $response = $client.GetAsync([string]$request.url).GetAwaiter().GetResult()
            try {
                $code = [int]$response.StatusCode
                $count = 0
                if ($code -eq 200) {
                    $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                    [IO.File]::WriteAllBytes([string]$request.path, $bytes)
                    $count = $bytes.Length
                }
                $result = @{code=$code;bytes=$count;error=''}
            } finally { $response.Dispose() }
        } catch {
            $result = @{code=0;bytes=0;error=$_.Exception.Message}
        }
        [Console]::WriteLine(($result | ConvertTo-Json -Compress))
    }
} finally { $client.Dispose() }

