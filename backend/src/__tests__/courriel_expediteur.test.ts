/**
 * Les courriels partent du domaine quand il est configuré, et disent
 * pourquoi on les reçoit.
 *
 * Les codes partaient d'une adresse Gmail personnelle nommée « PronoWin » et
 * arrivaient en indésirables (3 octobre 2026). `EMAIL_FROM` et
 * `EMAIL_REPLY_TO` permettent d'envoyer depuis pronowin.space par un relais ;
 * sans elles, rien ne change.
 */
const envois: any[] = [];
jest.mock('nodemailer', () => ({
  createTransport: () => ({ sendMail: async (m: any) => { envois.push(m); return {}; } }),
}));

import { sendEmailOtp, envoyerAlerteAdmin, contenuCode } from '../services/email.service';

const ENV = { ...process.env };
beforeEach(() => {
  envois.length = 0;
  process.env = { ...ENV, SMTP_USER: 'compte@gmail.com', SMTP_PASS: 'x', NODE_ENV: 'test' };
  delete process.env.EMAIL_FROM;
  delete process.env.EMAIL_REPLY_TO;
  delete process.env.ADMIN_ALERT_EMAIL;
});
afterAll(() => { process.env = ENV; });

it('sans réglage, rien ne change : l\'identifiant SMTP expédie', async () => {
  await sendEmailOtp('membre@exemple.test', '482913');
  expect(envois[0].from).toBe('"PronoWin" <compte@gmail.com>');
  expect(envois[0].replyTo).toBeUndefined();
});

it('avec le domaine : expéditeur noreply, réponses vers la boîte de l\'équipe', async () => {
  process.env.SMTP_USER = '9abc12@smtp-brevo.com';
  process.env.EMAIL_FROM = 'PronoWin <noreply@pronowin.space>';
  process.env.EMAIL_REPLY_TO = 'pronowin2026@gmail.com';

  await sendEmailOtp('membre@exemple.test', '482913');
  expect(envois[0].from).toBe('PronoWin <noreply@pronowin.space>');
  expect(envois[0].replyTo).toBe('pronowin2026@gmail.com');

  // L'identifiant d'un relais n'est pas une boîte aux lettres : les alertes
  // vont à l'adresse de réponse quand ADMIN_ALERT_EMAIL manque.
  await envoyerAlerteAdmin('[PronoWin] essai', 'corps');
  expect(envois[1].to).toBe('pronowin2026@gmail.com');
});

it('le code est dans l\'objet, et le message dit pourquoi on le reçoit', () => {
  const c = contenuCode('482913');
  expect(c.subject).toBe('482913 est votre code PronoWin');
  for (const corps of [c.text, c.html]) {
    expect(corps).toContain('482913');
    expect(corps).toMatch(/connexion à l.application PronoWin/);
    expect(corps).toMatch(/expire dans 10 minutes/);
  }
});
