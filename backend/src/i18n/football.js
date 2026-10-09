// Shared deterministic football labels. Raw provider fields are never mutated.
'use strict';
const catalog = require('./football-catalog.json');
const norm = s => String(s ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
const lang = l => String(l ?? 'fr').toLowerCase().startsWith('en') ? 'en' : 'fr';
function lookup(table, value, language = 'fr') {
    const key = norm(value);
    const item = catalog[table].find(x => [x.en, x.fr, ...x.aliases].some(a => norm(a) === key));
    return { text: item ? item[lang(language)] : String(value ?? ''), known: !!item };
}
function country(value, language = 'fr') {
    const result = lookup('countries', value, language);
    if (result.known)
        return result.text;
    const m = String(value ?? '').match(/^(.+?) (U\d{2}|W)$/);
    return m ? country(m[1], language) + ' ' + m[2] : String(value ?? '');
}
function market(value, language = 'fr') { return lookup('markets', value, language); }
function selection(value, language = 'fr', home = '', away = '', depth = 0) {
    const s = String(value ?? '').trim(), l = lang(language);
    if (depth > 4)
        return { text: s, known: false };
    // Protect supplied team names before examining selection grammar.
    for (const team of [home, away])
        if (team && [team, country(team, 'fr'), country(team, 'en')].some(t => norm(t) === norm(s)))
            return { text: country(team, l), known: true };
    const basic = lookup('selections', s, l);
    if (basic.known) {
        if (norm(s) === 'home' || norm(s) === 'domicile')
            return { text: home ? country(home, l) : basic.text, known: true };
        if (norm(s) === 'away' || norm(s) === 'extérieur')
            return { text: away ? country(away, l) : basic.text, known: true };
        return basic;
    }
    const threshold = s.match(/^(Over|Under|Exactly|Plus de|Moins de|Exactement|Home|Away|Domicile|Extérieur)\s+([+-]?\d+(?:[.,]\d+)?)$/i);
    if (threshold) {
        const t = selection(threshold[1], l, home, away, depth + 1);
        return { text: t.text + ' ' + threshold[2].replace(l === 'fr' ? '.' : ',', l === 'fr' ? ',' : '.'), known: t.known };
    }
    if (/^[+-]?\d+(?:[.,]\d+)?$/.test(s) || /^\d+\s*[-:]\s*\d+$/.test(s))
        return { text: s, known: true };
    if (['1X', 'X2', '12', '1', 'X', '2'].includes(s.toUpperCase()))
        return { text: s.toUpperCase(), known: true };
    for (const [re, fr, en] of [[/\s+(?:or|ou)\s+/i, ' ou ', ' or '], [/\s+(?:and|et)\s+/i, ' et ', ' and '], [/\s*\/\s*/, ' / ', ' / ']]) {
        const parts = s.split(re);
        if (parts.length > 1 && parts.length <= 4) {
            const values = parts.map(p => selection(p, l, home, away, depth + 1));
            if (values.every(x => x.known))
                return { text: values.map(x => x.text).join(l === 'fr' ? fr : en), known: true };
        }
    }
    return { text: s, known: false };
}
function prediction(value, language = 'fr', home = '', away = '') {
    const s = String(value ?? '').trim(), l = lang(language), colon = s.indexOf(':');
    if (colon > 0) {
        const m = market(s.slice(0, colon), l);
        if (m.known) {
            const v = selection(s.slice(colon + 1), l, home, away);
            return { text: m.text + ' : ' + v.text, known: v.known };
        }
    }
    const m = market(s, l);
    if (m.known)
        return m;
    if (/^(?:Match nul|Draw)$/i.test(s))
        return { text: l === 'fr' ? 'Match nul' : 'Draw', known: true };
    const goals = s.match(/^([+-])(\d+(?:[.,]\d+)?) (?:buts?|goals?)$/i) || s.match(/^(Plus de|Moins de|Over|Under) (\d+(?:[.,]\d+)?) (?:buts?|goals?)$/i);
    if (goals) {
        const over = ['+', 'plus de', 'over'].includes(goals[1].toLowerCase());
        const n = goals[2].replace(l === 'fr' ? '.' : ',', l === 'fr' ? ',' : '.');
        return { text: (l === 'fr' ? (over ? 'Plus de ' : 'Moins de ') : (over ? 'Over ' : 'Under ')) + n + (l === 'fr' ? ' buts' : ' goals'), known: true };
    }
    const win = s.match(/^(.+?) (?:gagne|wins)$/i);
    if (win) {
        const v = selection(win[1], l, home, away);
        if (v.known)
            return { text: v.text + (l === 'fr' ? ' gagne' : ' wins'), known: true };
    }
    return { text: s, known: false };
}
function round(value, language = 'fr') {
    const found = lookup('rounds', value, language);
    if (found.known)
        return found.text;
    for (const rule of catalog.roundRules)
        for (const p of rule.patterns) {
            const m = String(value ?? '').match(new RegExp(p, 'i'));
            if (m)
                return rule[lang(language)].replace(/\{(\d+)\}/g, (_, i) => m[Number(i)]);
        }
    return String(value ?? '');
}
function absence(value, language = 'fr') { return lookup('absences', value, language); }
function transfer(value, language = 'fr') { return lookup('transfers', value, language); }
function status(value, language = 'fr') { return lookup('statuses', value, language); }
module.exports = { catalog, market, selection, prediction, country, round, absence, transfer, status };
