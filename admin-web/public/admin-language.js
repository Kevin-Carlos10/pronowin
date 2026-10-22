'use strict';
function setAdminLanguage(language) {
 if (!['fr','en'].includes(language)) return;
 document.cookie = 'pw_admin_language=' + language + '; Path=/; Max-Age=31536000; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
 location.reload();
}
