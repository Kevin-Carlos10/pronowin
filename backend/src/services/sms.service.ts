import { journal } from '../utils/logger';
export async function sendSmsOtp(
  phoneNumber: string,
  code: string,
): Promise<void> {

  journal.info('==========================');
  journal.info(`[SMS DEV] OTP pour ${phoneNumber}`);
  journal.info(`[CODE OTP] ${code}`);
  journal.info('==========================');

  return;
}