import axios from 'axios';
import logger from '../utils/logger';

const WA_API_VERSION = 'v21.0';
const WA_BASE_URL    = `https://graph.facebook.com/${WA_API_VERSION}`;

/**
 * Envoie un OTP via WhatsApp Business (Meta Cloud API).
 *
 * Variables d'environnement requises :
 *   WHATSAPP_PHONE_NUMBER_ID  — ID du numéro WhatsApp Business
 *   WHATSAPP_ACCESS_TOKEN     — Token d'accès permanent Meta
 *   WHATSAPP_TEMPLATE_NAME    — Nom du template (défaut: "authentication" = template natif Meta)
 *   WHATSAPP_TEMPLATE_LANG    — Code langue (défaut: fr)
 *
 * Le template "authentication" est natif Meta : auto-approuvé, envoie le code
 * avec un bouton "Copier le code". Aucune création manuelle requise.
 */
export async function sendWhatsAppOtp(phoneNumber: string, code: string): Promise<void> {
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const accessToken   = process.env.WHATSAPP_ACCESS_TOKEN;
  const templateName  = process.env.WHATSAPP_TEMPLATE_NAME ?? 'authentication';
  const templateLang  = process.env.WHATSAPP_TEMPLATE_LANG ?? 'fr';

  // Sans credentials configurés : log uniquement (dev / CI)
  if (!phoneNumberId || !accessToken) {
    logger.warn(`[WhatsApp DEV] OTP pour ${phoneNumber} : ${code}`);
    return;
  }

  // WhatsApp exige le format international sans "+" (ex: 22670000000)
  const waPhone = phoneNumber.replace(/^\+/, '');

  // Construire les components selon le type de template
  const components = buildComponents(templateName, code);

  const payload: any = {
    messaging_product: 'whatsapp',
    to:   waPhone,
    type: 'template',
    template: {
      name:     templateName,
      language: { code: templateLang },
      ...(components.length > 0 ? { components } : {}),
    },
  };

  try {
    await axios.post(
      `${WA_BASE_URL}/${phoneNumberId}/messages`,
      payload,
      {
        headers: {
          Authorization:  `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        timeout: 10_000,
      },
    );
    logger.info(`[WhatsApp] OTP envoyé à ${waPhone}`);
  } catch (err: any) {
    const detail = err.response?.data?.error?.message ?? err.message;
    logger.error(`[WhatsApp] Échec envoi OTP à ${waPhone} : ${detail}`);
    throw new Error(`WhatsApp OTP failed: ${detail}`);
  }
}

/**
 * Construit les components selon le template utilisé.
 *
 * - "authentication" : template natif Meta (bouton copy_code auto-approuvé)
 * - tout autre nom   : template custom avec paramètre body {{1}} = code
 * - "hello_world"    : template de test, aucun paramètre
 */
function buildComponents(templateName: string, code: string) {
  if (templateName === 'hello_world') {
    return []; // template de test, pas de paramètre
  }

  if (templateName === 'authentication') {
    // Template natif Meta OTP — body {{1}} + bouton copy_code
    return [
      {
        type: 'body',
        parameters: [{ type: 'text', text: code }],
      },
      {
        type:     'button',
        sub_type: 'url',
        index:    '0',
        parameters: [{ type: 'text', text: code }],
      },
    ];
  }

  // Template auth Meta (ex: pronowin_otp) — body {{1}} + bouton copy_code
  return [
    {
      type: 'body',
      parameters: [{ type: 'text', text: code }],
    },
    {
      type:     'button',
      sub_type: 'copy_code',
      index:    '0',
      parameters: [{ type: 'coupon_code', coupon_code: code }],
    },
  ];
}
