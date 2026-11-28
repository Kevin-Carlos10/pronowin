'use strict';
const en = require('./ui.en.json');
const { nomPays } = require('./noms_pays');
function normalizeLanguage(value) { return value === 'en' ? 'en' : 'fr'; }
function translator(language) { return text => language === 'en' ? (en[text] || text) : text; }
function middleware(req,res,next) {
 res.locals.adminLanguage=normalizeLanguage(req.cookies?.pw_admin_language);
 res.locals.tAdmin=translator(res.locals.adminLanguage);
 // Le nom du pays, pas son code (« BF » → « Burkina Faso »), dans la langue de l'administration.
 res.locals.nomPays=code => nomPays(code, res.locals.adminLanguage);
 next();
}
module.exports={middleware,translator,normalizeLanguage};
