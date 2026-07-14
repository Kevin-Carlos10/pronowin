import nodemailer from 'nodemailer';
import logger from '../utils/logger';

const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST   ?? 'smtp.gmail.com',
  port:   parseInt(process.env.SMTP_PORT ?? '587'),
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

export async function sendEmailOtp(email: string, code: string): Promise<void> {
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    logger.warn(`[Email DEV] OTP pour ${email} : ${code}`);
    return;
  }

  await transporter.sendMail({
    from:    `"PronoWin" <${process.env.SMTP_USER}>`,
    to:      email,
    subject: 'Votre code de vérification PronoWin',
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

  logger.info(`[Email] OTP envoyé à ${email}`);
}
