/**
 * Direct phone login is allowed only outside production, and only when the
 * flag is explicitly true. Production ignores the flag.
 */
export function resolveOtpBypassMode(env = process.env) {
  const nodeEnv = env.NODE_ENV || "development";
  const requested =
    String(env.OTP_BYPASS_MODE ?? "").trim().toLowerCase() === "true";
  return requested && nodeEnv !== "production";
}
