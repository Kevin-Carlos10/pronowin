<#
.SYNOPSIS
  Fabrique un binaire PronoWin en choisissant explicitement son canal.

.DESCRIPTION
  Le canal gouverne le paywall, les prix, l'affichage des bookmakers et le
  mécanisme de mise à jour. Se tromper de canal en publiant sur Play n'est pas
  une mise à jour refusée : c'est un motif de retrait d'application.

  Ce script existe pour qu'on ne tape plus jamais `flutter build` à la main
  pour une release. Le paramètre -Canal est obligatoire : il n'y a pas de
  valeur par défaut, donc pas d'oubli possible.

.PARAMETER Canal
  play   → App Bundle pour Google Play, achat intégré, aucune mention bookmaker.
  direct → APK pour téléchargement depuis le site, Mobile Money, affiliation.

.PARAMETER ApiUrl
  URL de l'API à embarquer. Obligatoire pour une release : le défaut du code
  pointe sur l'émulateur (10.0.2.2), ce qui produirait un binaire incapable de
  joindre quoi que ce soit sur un vrai téléphone.

.EXAMPLE
  .\tool\build.ps1 -Canal play   -ApiUrl https://api.pronowin.com/api/v1
  .\tool\build.ps1 -Canal direct -ApiUrl https://api.pronowin.com/api/v1
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('play', 'direct')]
  [string]$Canal,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^https?://')]
  [string]$ApiUrl
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if ($Canal -eq 'play') {
  $storeBuild = 'true'
  $cible      = 'appbundle'
  $sortie     = 'build\app\outputs\bundle\release\app-release.aab'
  $resume     = 'Google Play — achat integre, bookmakers masques'
} else {
  $storeBuild = 'false'
  $cible      = 'apk'
  $sortie     = 'build\app\outputs\flutter-apk\app-release.apk'
  $resume     = 'Telechargement direct — Mobile Money, affiliation active'
}

Write-Host ''
Write-Host "  Canal      : $Canal" -ForegroundColor Cyan
Write-Host "  STORE_BUILD: $storeBuild"
Write-Host "  API        : $ApiUrl"
Write-Host "  Profil     : $resume"
Write-Host ''

flutter build $cible --release `
  --dart-define=STORE_BUILD=$storeBuild `
  --dart-define=API_BASE_URL=$ApiUrl

if ($LASTEXITCODE -ne 0) {
  Write-Host ''
  Write-Host "  Echec de la compilation (code $LASTEXITCODE)." -ForegroundColor Red
  exit $LASTEXITCODE
}

Write-Host ''
if (Test-Path $sortie) {
  $mo = [math]::Round((Get-Item $sortie).Length / 1MB, 1)
  Write-Host "  OK  $sortie  ($mo Mo)" -ForegroundColor Green
} else {
  Write-Host "  Compilation reussie mais $sortie est introuvable." -ForegroundColor Yellow
}

if ($Canal -eq 'direct') {
  Write-Host ''
  Write-Host '  Rappel : cet APK ne se met pas a jour tout seul.' -ForegroundColor Yellow
  Write-Host '  Publiez-le, puis mettez a jour APK_LATEST_VERSION et APK_URL'
  Write-Host '  dans le .env du backend, sinon personne ne saura qu''il existe.'
}
Write-Host ''
