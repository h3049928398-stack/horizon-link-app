param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FlutterArguments)
. (Join-Path $PSScriptRoot 'android-env.ps1')
if (($FlutterArguments -contains 'run') -or (($FlutterArguments -contains 'build') -and (($FlutterArguments -contains 'apk') -or ($FlutterArguments -contains 'appbundle')))) {
    if ($env:ANDROID_HOME) { & (Join-Path $PSScriptRoot 'scripts\ensure_android_cache.ps1') }
}
$env:FLUTTER_ROOT = 'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk\flutter'
$env:PUB_CACHE = Join-Path $PSScriptRoot '.tools\pub-cache'
$env:APPDATA = Join-Path $PSScriptRoot '.tools\appdata'
$env:TEMP = Join-Path $PSScriptRoot '.tools\tmp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Path $env:APPDATA,$env:TEMP -Force | Out-Null
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
& "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe" "$env:FLUTTER_ROOT\bin\cache\flutter_tools.snapshot" --no-version-check @FlutterArguments
exit $LASTEXITCODE
