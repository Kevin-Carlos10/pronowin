export async function sendSmsOtp(
  phoneNumber: string,
  code: string,
): Promise<void> {

  console.log('==========================');
  console.log(`[SMS DEV] OTP pour ${phoneNumber}`);
  console.log(`[CODE OTP] ${code}`);
  console.log('==========================');

  return;
}