param([string]$DeviceId = '', [switch]$SkipBuild, [string]$WeeklyContentUrl = '', [ValidateSet('debug','profile')][string]$Mode = 'debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if ($SkipBuild -and $PSBoundParameters.ContainsKey('WeeklyContentUrl')) { throw 'Changing WeeklyContentUrl requires a new build; omit -SkipBuild.' }
# This is a public content URL, never a cloud credential. Keep ordinary debug
# rebuilds connected after the initial COS setup. Explicit arguments override it.
if (-not $PSBoundParameters.ContainsKey('WeeklyContentUrl') -and -not $SkipBuild) {
    $weeklyConfiguration = Join-Path $projectRoot 'config\weekly-content.json'
    if (Test-Path -LiteralPath $weeklyConfiguration) {
        $WeeklyContentUrl = [string](Get-Content -LiteralPath $weeklyConfiguration -Raw | ConvertFrom-Json).url
    }
}
if ($WeeklyContentUrl) {
    $weeklyUri = $null
    if (-not [Uri]::TryCreate($WeeklyContentUrl, [UriKind]::Absolute, [ref]$weeklyUri) -or $weeklyUri.Scheme -ne 'https' -or $weeklyUri.UserInfo -or $weeklyUri.Fragment) {
        throw 'WeeklyContentUrl must be an HTTPS URL without credentials or fragment.'
    }
    if ($SkipBuild) { throw 'Changing WeeklyContentUrl requires a new build; omit -SkipBuild.' }
}
. (Join-Path $projectRoot 'android-env.ps1')
if (-not $env:ANDROID_HOME) { throw 'Android SDK is not configured. See docs/ANDROID_DEBUG.md.' }
$adb = Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw 'Android platform-tools are missing.' }
$deviceLines = & $adb devices
$connectedDevices = @($deviceLines | ForEach-Object {
    if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] }
})
if (-not $DeviceId) {
    if ($connectedDevices.Count -ne 1) {
        & $adb devices -l
        throw 'Connect and authorize one Android device, or pass -DeviceId.'
    }
    $DeviceId = $connectedDevices[0]
}
if ($DeviceId -notin $connectedDevices) { throw 'Selected device is not connected and authorized.' }
if (-not (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME 'platforms\android-36\android.jar'))) {
    throw 'Android 36 SDK platform is not installed yet.'
}
Write-Host "Flutter USB $Mode session (profile is for local validation, not store distribution)."
Push-Location (Join-Path $projectRoot 'flutter_app')
try {
    if (-not $SkipBuild) {
        $deviceAbi = (& $adb -s $DeviceId shell getprop ro.product.cpu.abi).Trim()
        $targetPlatform = switch ($deviceAbi) {
            'arm64-v8a' { 'android-arm64' }
            'armeabi-v7a' { 'android-arm' }
            'x86_64' { 'android-x64' }
            default { throw "Unsupported Android device ABI: $deviceAbi" }
        }
        $buildArguments = @('build','apk','--no-pub',"--$Mode",'--target-platform',$targetPlatform)
        $publicMetadata = Join-Path $projectRoot '.tools/release/public-metadata.json'
        if (Test-Path -LiteralPath $publicMetadata) { $buildArguments += "--dart-define-from-file=$publicMetadata" }
        if ($WeeklyContentUrl) { $buildArguments += "--dart-define=WEEKLY_CONTENT_URL=$WeeklyContentUrl" }
        $buildRoot = Join-Path $projectRoot 'flutter_app'
        if ($Mode -eq 'profile') { $buildRoot = & (Join-Path $PSScriptRoot 'prepare_android_build_workspace.ps1') -ProjectRoot $projectRoot }
        Push-Location $buildRoot
        try { & (Join-Path $projectRoot 'flutter.ps1') -FlutterArguments $buildArguments }
        finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { throw 'Android debug build failed.' }
        if ($Mode -eq 'profile') {
            New-Item -ItemType Directory -Path (Join-Path $projectRoot 'artifacts/release-prep') -Force | Out-Null
            $originalOutput = Join-Path $projectRoot 'flutter_app/build/app/outputs/flutter-apk'
            New-Item -ItemType Directory -Path $originalOutput -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $buildRoot 'build/app/outputs/flutter-apk/app-profile.apk') -Destination (Join-Path $originalOutput 'app-profile.apk') -Force
            $buildRoot | Set-Content -LiteralPath (Join-Path $projectRoot 'artifacts/release-prep/profile-build-workspace.txt')
        }
    }
    $builtApk = Join-Path $projectRoot "flutter_app\build\app\outputs\flutter-apk\app-$Mode.apk"
    if (-not (Test-Path -LiteralPath $builtApk)) { throw 'No debug APK exists. Run without -SkipBuild first.' }
    # Android aapt/ADB on Windows cannot reliably read APKs from non-ASCII paths.
    $stagingDirectory = Join-Path $androidToolRoot 'horizon-artifacts'
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    $stagedApk = Join-Path $stagingDirectory "horizon-link-$Mode.apk"
    Copy-Item -LiteralPath $builtApk -Destination $stagedApk -Force
    & (Join-Path $projectRoot 'flutter.ps1') -FlutterArguments @('run','--no-pub',"--$Mode",'--device-id',$DeviceId,'--use-application-binary',$stagedApk)
    $debugExitCode = $LASTEXITCODE
} finally { Pop-Location }
exit $debugExitCode
