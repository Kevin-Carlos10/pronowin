import nodemailer from 'nodemailer';
import logger from '../utils/logger';
import { ServiceIndisponible } from '../utils/erreurs';

const port = parseInt(process.env.SMTP_PORT ?? '587');
const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST   ?? 'smtp.gmail.com',
  port,
  // 465 parle TLS d'emblée ; 587 (Gmail, Brevo) commence en clair puis
  // passe en TLS (STARTTLS).
  secure: port === 465,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

/**
 * L'expéditeur des courriels.
 *
 * Il était toujours l'identifiant SMTP : une adresse Gmail personnelle
 * affichée sous le nom « PronoWin ». Une marque sur une adresse gratuite,
 * pour un message qui contient un code : c'est le profil d'un hameçonnage,
 * et Gmail rangeait les codes en indésirables (constaté sur les vidéos du
 * 3 octobre 2026).
 *
 * `EMAIL_FROM` permet d'envoyer depuis le domaine (« PronoWin
 * <noreply@pronowin.space> ») par un relais qui le signe — l'identifiant
 * d'un tel relais n'est d'ailleurs pas une adresse. Sans elle, rien ne
 * change.
 */
function expediteur(nom = 'PronoWin'): string {
  return process.env.EMAIL_FROM?.trim() || `"${nom}" <${process.env.SMTP_USER}>`;
}

/** Où arrivent les réponses : une adresse d'envoi « noreply » ne lit rien. */
function adresseReponse(): string | undefined {
  return process.env.EMAIL_REPLY_TO?.trim() || undefined;
}

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

/**
 * Le courriel du code de connexion.
 *
 * Le code est dans l'objet : il se lit dans la notification du téléphone,
 * sans ouvrir la messagerie — c'est là qu'on le cherche, l'application
 * ouverte à côté. Et le message dit pourquoi on le reçoit : un code sans
 * contexte est ce qu'un filtre, et un lecteur, prennent pour une arnaque.
 */
export function contenuCode(code: string): { subject: string; text: string; html: string } {
  const raison = 'Vous recevez cet e-mail parce qu\'une connexion à l\'application PronoWin '
    + 'a été demandée avec cette adresse. Si ce n\'est pas vous, ignorez-le : '
    + 'personne ne pourra se connecter sans ce code.';
  return {
    subject: `${code} est votre code PronoWin`,
    text: `Votre code de connexion PronoWin : ${code}\n\n`
      + `Il expire dans 10 minutes. Ne le communiquez à personne : l'équipe PronoWin ne vous le demandera jamais.\n\n`
      + `${raison}\n\n— PronoWin · https://pronowin.space`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;color:#1a1a2e">
        <h2 style="margin:0 0 16px">PronoWin</h2>
        <p>Votre code de connexion :</p>
        <div style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#c2410c;padding:12px 0">${code}</div>
        <p>Il expire dans 10 minutes. Ne le communiquez à personne : l'équipe PronoWin ne vous le demandera jamais.</p>
        <p style="color:#666;font-size:13px;margin-top:24px">${raison}</p>
        <p style="color:#666;font-size:13px">PronoWin · <a href="https://pronowin.space" style="color:#666">pronowin.space</a></p>
      </div>
    `,
  };
}

async function envoyerCode(email: string, code: string): Promise<void> {
  await transporter.sendMail({
    from:    expediteur(),
    replyTo: adresseReponse(),
    to:      email,
    ...contenuCode(code),
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
  // Avec un relais, l'identifiant SMTP n'est pas une boîte aux lettres :
  // l'adresse de réponse passe avant lui.
  const destinataire = process.env.ADMIN_ALERT_EMAIL ?? adresseReponse() ?? process.env.SMTP_USER;

  if (!process.env.SMTP_USER || !process.env.SMTP_PASS || !destinataire) {
    logger.warn(`[Alerte] SMTP non configuré — non envoyée : ${sujet}`);
    return false;
  }

  try {
    await transporter.sendMail({
      from:    expediteur('PronoWin — alerte'),
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
