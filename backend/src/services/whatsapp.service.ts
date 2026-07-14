import axios from 'axios';
import logger from '../utils/logger';

const WA_API_VERSION   = 'v21.0';
const WA_BASE_URL      = `https://graph.facebook.com/${WA_API_VERSION}`;

/**
 * Envoie un OTP via WhatsApp Business (Meta Cloud API).
 *
 * Variables d'environnement requises :
 *   WHATSAPP_PHONE_NUMBER_ID  — ID du numéro WhatsApp Business (ex: 123456789012345)
 *   WHATSAPP_ACCESS_TOKEN     — Token d'accès permanent Meta
 *   WHATSAPP_TEMPLATE_NAME    — Nom du template approuvé (défaut: pronowin_otp)
 *   WHATSAPP_TEMPLATE_LANG    — Code langue du template (défaut: fr)
 */
export async function sendWhatsAppOtp(phoneNumber: string, code: string): Promise<void> {
  const phoneNumberId  = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const accessToken    = process.env.WHATSAPP_ACCESS_TOKEN;
  const templateName   = process.env.WHATSAPP_TEMPLATE_NAME ?? 'pronowin_otp';
  const templateLang   = process.env.WHATSAPP_TEMPLATE_LANG ?? 'fr';

  // En développement (ou si les variables ne sont pas configurées) : log uniquement
  if (!phoneNumberId || !accessToken) {
    logger.warn(`[WhatsApp DEV] OTP pour ${phoneNumber} : ${code}`);
    return;
  }

  // WhatsApp exige le format international sans le "+" (ex: 22670000000)
  const waPhone = phoneNumber.replace(/^\+/, '');

  await axios.post(
    `${WA_BASE_URL}/${phoneNumberId}/messages`,
    {
      messaging_product: 'whatsapp',
      to:   waPhone,
      type: 'template',
      template: {
        name:     templateName,
        language: { code: templateLang },
        // hello_world n'a pas de paramètres ; pronowin_otp en a un (le code)
        ...(templateName !== 'hello_world' ? {
          components: [
            {
              type: 'body',
              parameters: [{ type: 'text', text: code }],
            },
          ],
        } : {}),
      },
    },
    {
      headers: {
        Authorization:  `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      timeout: 10_000,
    },
  );

  logger.info(`[WhatsApp] OTP envoyé à ${waPhone}`);
}
