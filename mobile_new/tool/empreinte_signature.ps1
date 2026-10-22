# Empreintes SHA du certificat qui signe REELLEMENT l'APK.
#
# Pourquoi ce script existe
# -------------------------
# L'empreinte a d'abord ete lue depuis le keystore, par un script qui exportait
# le certificat sans verifier ce qu'il avait extrait. Il a calcule l'empreinte
# d'autre chose et l'a presentee comme celle du certificat. L'empreinte fausse a
# ete enregistree chez Google, et la connexion Google a echoue pendant des
# heures avec un message ("Account reauth failed") qui ne designait rien.
#
# La source de verite n'est pas le keystore : c'est l'APK. Un keystore peut
# contenir plusieurs alias, la configuration Gradle peut en designer un autre,
# et seul l'APK dit avec quel certificat il a ete signe. Ce script interroge
# donc l'APK, avec apksigner, qui lit la signature elle-meme.
#
#   .\tool\empreinte_signature.ps1                     (APK release par defaut)
#   .\tool\empreinte_signature.ps1 -Apk chemin\vers.apk

param(
    [string]$Apk = "build\app\outputs\flutter-apk\app-release.apk"
)

$racine = Split-Path -Parent $PSScriptRoot
$chemin = Join-Path $racine $Apk

if (-not (Test-Path $chemin)) {
    Write-Host "APK introuvable : $chemin" -ForegroundColor Red
    Write-Host "Construisez-le d'abord : flutter build apk --release"
    exit 1
}

$apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools\*\apksigner.bat" -ErrorAction SilentlyContinue |
             Sort-Object FullName | Select-Object -Last 1
if (-not $apksigner) {
    Write-Host "apksigner introuvable dans le SDK Android." -ForegroundColor Red
    exit 1
}

$sortie = & $apksigner.FullName verify --print-certs -v $chemin 2>$null

$sha1   = ($sortie | Select-String 'certificate SHA-1 digest:\s*([0-9a-f]+)').Matches.Groups[1].Value
$sha256 = ($sortie | Select-String 'certificate SHA-256 digest:\s*([0-9a-f]+)').Matches.Groups[1].Value
$dn     = ($sortie | Select-String 'certificate DN:\s*(.+)$').Matches.Groups[1].Value

if (-not $sha1) {
    Write-Host "Aucune signature lisible dans l'APK." -ForegroundColor Red
    exit 1
}

function Formater($hex) {
    ($hex.ToUpper() -split '(..)' | Where-Object { $_ }) -join ':'
}

Write-Host ""
Write-Host "  APK      : $Apk"
Write-Host "  Signe par: $dn"
Write-Host ""
Write-Host "  SHA-1   : $(Formater $sha1)" -ForegroundColor Cyan
Write-Host "  SHA-256 : $(Formater $sha256)" -ForegroundColor Cyan
Write-Host ""

# Confrontation avec ce qui est declare chez Google : c'est ce rapprochement,
# et non l'empreinte seule, qui aurait revele l'erreur des le premier jour.
$cfg = Join-Path $racine "android\app\google-services.json"
if (Test-Path $cfg) {
    $json = Get-Content $cfg -Raw | ConvertFrom-Json
    $app = $json.client | Where-Object { $_.client_info.android_client_info.package_name -eq 'com.pronowin.app' }
    $declarees = @($app.oauth_client | Where-Object { $_.android_info } | ForEach-Object {
        Formater $_.android_info.certificate_hash
    })

    if ($declarees.Count -eq 0) {
        Write-Host "  Aucune empreinte declaree dans google-services.json." -ForegroundColor Yellow
        Write-Host "  Enregistrez la SHA-1 ci-dessus dans la console Firebase." -ForegroundColor Yellow
    }
    elseif ($declarees -contains (Formater $sha1)) {
        Write-Host "  Concorde avec google-services.json." -ForegroundColor Green
    }
    else {
        Write-Host "  DIVERGENCE" -ForegroundColor Red
        Write-Host "    declaree(s) chez Google : $($declarees -join ', ')" -ForegroundColor Red
        Write-Host "    signature reelle        : $(Formater $sha1)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  La connexion Google echouera avec « Account reauth failed »." -ForegroundColor Red
        Write-Host "  Enregistrez la signature reelle dans la console Firebase," -ForegroundColor Red
        Write-Host "  puis retelechargez google-services.json." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""
