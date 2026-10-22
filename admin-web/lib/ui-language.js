'use strict';
const en = require('./ui.en.json');
function normalizeLanguage(value) { return value === 'en' ? 'en' : 'fr'; }
function translator(language) { return text => language === 'en' ? (en[text] || text) : text; }
function middleware(req,res,next) {
 res.locals.adminLanguage=normalizeLanguage(req.cookies?.pw_admin_language);
 res.locals.tAdmin=translator(res.locals.adminLanguage);
 next();
}
module.exports={middleware,translator,normalizeLanguage};
