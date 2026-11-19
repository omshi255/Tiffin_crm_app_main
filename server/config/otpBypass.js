/**
 * Phone login skips SMS when OTP_BYPASS_MODE=true.
 * Set OTP_BYPASS_MODE=false to turn the OTP step back on.
 */
export function resolveOtpBypassMode(env = process.env) {
  return String(env.OTP_BYPASS_MODE ?? "").trim().toLowerCase() === "true";
}
