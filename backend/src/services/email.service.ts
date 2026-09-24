import nodemailer from 'nodemailer';
import logger from '../utils/logger';
import { ServiceIndisponible } from '../utils/erreurs';

const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST   ?? 'smtp.gmail.com',
  port:   parseInt(process.env.SMTP_PORT ?? '587'),
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

/**
 * Envoie un code de connexion par courriel.
 *
 * Sans identifiants SMTP, la fonction écrivait le code dans le journal et
 * rendait la main comme si l'envoi avait eu lieu — en production aussi, rien
 * ne limitait ce repli au développement. L'application annonçait « code
 * envoyé » alors que rien n'était parti, et le code de connexion devenait
 * lisible par quiconque lit les journaux (constat I8 de l'audit du
 * 24 septembre 2026).
 *
 * Le repli reste pour le développement et les bancs d'essai. En production,
 * un canal non configuré se dit : 503, et aucun code dans le journal.
 */
export async function sendEmailOtp(email: string, code: string): Promise<void> {
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    if (process.env.NODE_ENV === 'production') {
      logger.error('[Email] SMTP non configuré : code de connexion non envoyé.');
      throw new ServiceIndisponible(
        'L\'envoi du code par e-mail est momentanément indisponible. '
        + 'Réessayez plus tard ou utilisez WhatsApp.', 'CANAL_EMAIL_INDISPONIBLE');
    }
    logger.warn(`[Email DEV] OTP pour ${email} : ${code}`);
    return;
  }

  try {
    await envoyerCode(email, code);
  } catch (e: any) {
    // Le message du serveur SMTP (« Invalid login: 535… ») n'a rien à faire
    // dans une réponse d'API : il reste dans le journal.
    logger.error(`[Email] Échec d'envoi du code à ${email} : ${e?.message ?? e}`);
    throw new ServiceIndisponible(
      'Le code n\'a pas pu être envoyé par e-mail. Réessayez dans un instant.',
      'CANAL_EMAIL_ECHEC');
  }
  logger.info(`[Email] OTP envoyé à ${email}`);
}

async function envoyerCode(email: string, code: string): Promise<void> {
  await transporter.sendMail({
    from:    `"PronoWin" <${process.env.SMTP_USER}>`,
    to:      email,
    subject: 'Votre code de vérification PronoWin',
    text: `PronoWin\n\nVotre code de vérification est : ${code}\n\nCe code expire dans 10 minutes. Ne le partagez avec personne.`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#1a1a2e">PronoWin</h2>
        <p>Votre code de vérification est :</p>
        <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#e94560;padding:16px 0">
          ${code}
        </div>
        <p style="color:#666;font-size:13px">Ce code expire dans 10 minutes. Ne le partagez avec personne.</p>
      </div>
    `,
  });
}

/**
 * Prévient l'exploitant d'un incident.
 *
 * ── Pourquoi cela passe par le courriel déjà en place ─────────────────────
 *
 * Le transport SMTP de ce fichier sert depuis le début aux codes de connexion :
 * il est configuré, éprouvé, et personne n'a à saisir de nouveau secret pour
 * s'en servir. Un second canal aurait demandé un compte de plus, donc un mot
 * de passe de plus à confier et à faire tourner.
 *
 * ── Ce qu'il advient quand SMTP manque ────────────────────────────────────
 *
 * On renvoie `false` et on écrit dans le journal, sans lever. Une alerte est
 * un dispositif de secours : elle ne doit pas, en échouant, faire tomber ce
 * qu'elle surveille. Mais elle ne doit pas non plus se taire en silence — le
 * `false` est là pour que l'appelant puisse le compter.
 */
export async function envoyerAlerteAdmin(
  sujet: string,
  corps: string,
): Promise<boolean> {
  // Lue à l'appel et non au chargement du module : l'environnement d'un
  // processus de longue durée peut changer, et un banc doit pouvoir la poser.
  const destinataire = process.env.ADMIN_ALERT_EMAIL ?? process.env.SMTP_USER;

  if (!process.env.SMTP_USER || !process.env.SMTP_PASS || !destinataire) {
    logger.warn(`[Alerte] SMTP non configuré — non envoyée : ${sujet}`);
    return false;
  }

  try {
    await transporter.sendMail({
      from:    `"PronoWin — alerte" <${process.env.SMTP_USER}>`,
      to:      destinataire,
      subject: sujet,
      text:    corps,
    });
    logger.info(`[Alerte] envoyée à ${destinataire} : ${sujet}`);
    return true;
  } catch (err: any) {
    logger.error(`[Alerte] envoi impossible : ${sujet}`, { message: err?.message });
    return false;
  }
}
