# Identifiant OAuth **Web** du projet Firebase, lu depuis google-services.json.
#
# Le SDK Google a besoin de cet identifiant comme `serverClientId` : c'est lui
# qui devient l'audience du jeton, et donc ce que le backend verifie contre sa
# variable GOOGLE_CLIENT_IDS. Ce n'est PAS l'identifiant Android.
#
# On le lit dans le fichier de configuration plutot que de l'ecrire en dur dans
# les scripts de build : deux copies finiraient par diverger, et une divergence
# ici ne casse rien de visible — la connexion Google echoue simplement, avec un
# message que rien ne relie a la cause.
#
# Renvoie une chaine vide si le fichier manque ou n'a pas de client Web ;
# l'appelant decide quoi en faire.

function Get-GoogleWebClientId {
    $chemin = Join-Path $PSScriptRoot '..\android\app\google-services.json'
    if (-not (Test-Path $chemin)) { return '' }

    try {
        $cfg = Get-Content $chemin -Raw | ConvertFrom-Json
    } catch {
        return ''
    }

    foreach ($client in $cfg.client) {
        # On ne retient que l'application reellement construite : le projet
        # porte encore l'app `com.example.mobile_new` heritee du gabarit
        # Flutter, dont les identifiants ne valent pas pour nous.
        if ($client.client_info.android_client_info.package_name -ne 'com.pronowin.app') { continue }
        foreach ($oauth in $client.oauth_client) {
            if ($oauth.client_type -eq 3) { return $oauth.client_id }   # 3 = Web
        }
    }
    return ''
}
