# Lance l'app sur un vrai telephone Android connecte en USB.
# Refait adb reverse a chaque execution car cette redirection ne survit pas
# a une reconnexion USB (debranchement, redemarrage d'adb, etc.) - sans ca
# l'app ne peut pas atteindre le backend local et tombe en "Connection refused".

Write-Host "Redirection du port 3000 (telephone -> PC) via adb reverse..."
adb reverse tcp:3000 tcp:3000
if ($LASTEXITCODE -ne 0) {
    Write-Host "adb reverse a echoue - verifie que le telephone est branche et en mode debogage USB." -ForegroundColor Yellow
}

. (Join-Path $PSScriptRoot 'tool\google_client_id.ps1')
$googleId = Get-GoogleWebClientId
if ([string]::IsNullOrEmpty($googleId)) {
    Write-Host "Identifiant client Web introuvable - la connexion Google sera inoperante." -ForegroundColor Yellow
}

flutter run `
    --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1 `
    --dart-define=GOOGLE_SERVER_CLIENT_ID=$googleId
