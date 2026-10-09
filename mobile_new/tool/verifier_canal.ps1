<#
    Vérifie le canal de distribution, de bout en bout.

    Quatre choses doivent tenir ensemble pour qu'un build store soit sûr, et
    aucune n'implique les autres :

      1. le drapeau `--dart-define=STORE_BUILD` parvient au provider,
         dans les deux sens (canal_drapeau_test) ;
      2. chaque surface sensible est précédée d'une garde sur ce provider
         (canal_store_test) ;
      3. retirer une garde fait échouer le contrôle correspondant
         (injections_canal.js) ;
      4. rien d'autre n'a cassé au passage (suite complète).

    Les trois premiers points se valident en quelques secondes. Le quatrième
    est plus long : passez -Rapide pour le sauter pendant une mise au point.

        pwsh tool/verifier_canal.ps1
        pwsh tool/verifier_canal.ps1 -Rapide

    Sortie non nulle dès qu'un point échoue.
#>
param([switch]$Rapide)

$ErrorActionPreference = 'Continue'

# Sans cette ligne, la console rend « vérifié » en « vÃ©rifiÃ© » : le fichier
# est en UTF-8, la sortie console retombe sur la page de code du système.
# Le script ne fait qu'afficher, mais un rapport de vérification illisible
# invite à ne plus le lire.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Set-Location (Join-Path $PSScriptRoot '..')

$echecs = @()

function Etape([string]$titre, [scriptblock]$action) {
    Write-Host ''
    Write-Host "── $titre" -ForegroundColor Cyan
    & $action
    if ($LASTEXITCODE -ne 0) {
        $script:echecs += $titre
        Write-Host "   ÉCHEC" -ForegroundColor Red
    } else {
        Write-Host "   ok" -ForegroundColor Green
    }
}

# 1. Le drapeau atteint-il le provider ? Les deux sens comptent : un provider
#    qui répondrait toujours « store » passerait un contrôle à sens unique.
foreach ($valeur in @('true', 'false')) {
    Etape "drapeau STORE_BUILD=$valeur" {
        flutter test test/canal_drapeau_test.dart --dart-define=STORE_BUILD=$valeur
    }
}

# 2. Les gardes sont-elles en place devant chaque surface sensible ?
Etape 'gardes de canal' { flutter test test/canal_store_test.dart }

# 3. Une garde retirée fait-elle échouer son contrôle ? Sans ce point, les
#    deux précédents peuvent être verts sans rien prouver.
Etape 'injections — gardes'  { node tool/injections_canal.js }
Etape 'injections — drapeau' { python tool/injections_drapeau.py }

if (-not $Rapide) {
    Etape 'suite complète' { flutter test }
}

Write-Host ''
if ($echecs.Count -eq 0) {
    Write-Host 'Canal vérifié.' -ForegroundColor Green
    exit 0
}
Write-Host "$($echecs.Count) étape(s) en échec :" -ForegroundColor Red
foreach ($e in $echecs) { Write-Host "  - $e" -ForegroundColor Red }
exit 1
