# Local Android toolchain. Only affects commands launched from this project.
$androidToolRoot = 'C:\Users\30499\.codex\visualizations\2026\10\26\01a178ad-e9b5-7d92-9669-57e4fec3e57f\sdk'
$androidSdkPath = Join-Path $androidToolRoot 'android'
if (Test-Path -LiteralPath (Join-Path $androidSdkPath 'platform-tools\adb.exe')) {
    $env:ANDROID_HOME = $androidSdkPath
    $env:ANDROID_SDK_ROOT = $androidSdkPath
    $env:GRADLE_USER_HOME = Join-Path $androidToolRoot 'gradle-cache'
    $env:Path = (Join-Path $androidSdkPath 'platform-tools') + ';' + $env:Path
    $androidJavaPath = Join-Path $androidToolRoot 'jdk-25.0.5.0.3'
    if (Test-Path -LiteralPath (Join-Path $androidJavaPath 'bin\jlink.exe')) {
        $env:JAVA_HOME = $androidJavaPath
    }
}
