'use strict';
function optionalText(value, max = 50000) {
 if(value === undefined) return undefined;
 if(value === null || value === '') return null;
 if(typeof value !== 'string' || value.length > max) throw new Error('Traduction invalide ou trop longue.');
 return value.trim() || null;
}
module.exports = { optionalText };
