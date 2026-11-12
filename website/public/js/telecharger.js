/*
 * Page « Télécharger » (11 novembre 2026).
 *
 * Trois petites aides, toutes facultatives : sans elles, la page reste
 * complète (le code s'affiche, chaque fichier a son lien).
 *
 *  1. Copier le code de parrainage d'un geste.
 *  2. Mettre en tête la section du téléphone qui visite (iPhone ou Android).
 *  3. Proposer le fichier le plus léger qui convient, quand le navigateur dit
 *     l'architecture du téléphone. Sinon, l'APK complet, qui marche partout.
 */
(function () {
  'use strict';

  // 1. Copier le code.
  var bouton = document.querySelector('[data-copier]');
  if (bouton && navigator.clipboard && navigator.clipboard.writeText) {
    bouton.hidden = false;
    bouton.addEventListener('click', function () {
      navigator.clipboard.writeText(bouton.getAttribute('data-copier')).then(function () {
        bouton.textContent = 'Code copié';
      }, function () { /* sans presse-papiers, le code reste lisible */ });
    });
  }

  // 2. La section du téléphone qui visite, en premier.
  var ua = navigator.userAgent || '';
  var iphone = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var android = /Android/.test(ua);
  var sectionIos = document.getElementById('iphone');
  var sectionAndroid = document.getElementById('android');
  if (iphone && sectionIos && sectionAndroid && sectionAndroid.parentNode) {
    sectionAndroid.parentNode.insertBefore(sectionIos, sectionAndroid);
    sectionIos.classList.add('download-block--courant');
  } else if (android && sectionAndroid) {
    sectionAndroid.classList.add('download-block--courant');
  }

  // 3. Le fichier le plus léger qui convient.
  var principal = document.querySelector('[data-apk-principal]');
  var uad = navigator.userAgentData;
  if (!android || !principal || !uad || !uad.getHighEntropyValues) return;
  uad.getHighEntropyValues(['architecture', 'bitness']).then(function (v) {
    var abi = null;
    if (v.architecture === 'arm' && v.bitness === '64') abi = 'arm64-v8a';
    else if (v.architecture === 'arm' && v.bitness === '32') abi = 'armeabi-v7a';
    else if (v.architecture === 'x86' && v.bitness === '64') abi = 'x86_64';
    var lien = abi && document.querySelector('[data-abi="' + abi + '"]');
    if (!lien) return;
    principal.setAttribute('href', lien.getAttribute('href'));
    principal.textContent = lien.getAttribute('data-libelle');
    principal.setAttribute('data-abi-choisie', abi);
    var note = document.createElement('p');
    note.className = 'legal-note';
    note.textContent = 'Version adaptée à ton téléphone.';
    principal.parentNode.insertAdjacentElement('afterend', note);
  }, function () { /* pas d'information : l'APK complet reste proposé */ });
})();
