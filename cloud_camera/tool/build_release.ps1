param(
    [Parameter(Mandatory = $true)]
    [string]$DesktopCredentialsPath,

    [Parameter(Mandatory = $true)]
    [string]$AndroidServerCredentialsPath,

    [ValidateSet('All', 'Windows', 'Android')]
    [string]$Target = 'All',

    [string]$FlutterPath = 'flutter'
)

$ErrorActionPreference = 'Stop'

$desktopPath = (Resolve-Path -LiteralPath $DesktopCredentialsPath).Path
$androidServerPath = (Resolve-Path -LiteralPath $AndroidServerCredentialsPath).Path
$desktopJson = Get-Content -LiteralPath $desktopPath -Raw -Encoding utf8 | ConvertFrom-Json
$androidServerJson = Get-Content -LiteralPath $androidServerPath -Raw -Encoding utf8 | ConvertFrom-Json

if ($null -eq $desktopJson.installed) {
    throw 'DesktopCredentialsPath must reference a Desktop OAuth client.'
}
if ([string]::IsNullOrWhiteSpace([string]$desktopJson.installed.client_secret)) {
    throw 'Desktop OAuth JSON does not contain client_secret.'
}
if ($null -eq $androidServerJson.web) {
    throw 'AndroidServerCredentialsPath must reference a Web OAuth client.'
}

$desktopClientId = [string]$desktopJson.installed.client_id
$desktopClientSecret = [string]$desktopJson.installed.client_secret
$androidServerClientId = [string]$androidServerJson.web.client_id

if ([string]::IsNullOrWhiteSpace($desktopClientId) -or
    [string]::IsNullOrWhiteSpace($androidServerClientId)) {
    throw 'OAuth JSON does not contain client_id.'
}

$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $projectDirectory
try {
    if ($Target -in @('All', 'Windows')) {
        & $FlutterPath build windows --release `
            "--dart-define=GOOGLE_DESKTOP_CLIENT_ID=$desktopClientId" `
            "--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=$desktopClientSecret" `
            "--dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=$androidServerClientId"
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    }

    if ($Target -in @('All', 'Android')) {
        & $FlutterPath build apk --release `
            "--dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=$androidServerClientId"
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    }
} finally {
    Pop-Location
}
