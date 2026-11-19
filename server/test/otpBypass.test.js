import test from "node:test";
import assert from "node:assert/strict";
import mongoose from "mongoose";
import { resolveOtpBypassMode } from "../config/otpBypass.js";
import config from "../config/index.js";
import { sendOtpController } from "../controllers/auth.controller.js";
import User from "../models/User.model.js";
import {
  verifyAccessToken,
  verifyRefreshToken,
} from "../services/token.service.js";

test("OTP bypass is refused in production and when the flag is off", () => {
  assert.equal(
    resolveOtpBypassMode({ NODE_ENV: "production", OTP_BYPASS_MODE: "true" }),
    false
  );
  assert.equal(
    resolveOtpBypassMode({ NODE_ENV: "development", OTP_BYPASS_MODE: "true" }),
    true
  );
  assert.equal(
    resolveOtpBypassMode({ NODE_ENV: "development", OTP_BYPASS_MODE: "false" }),
    false
  );
  assert.equal(resolveOtpBypassMode({ OTP_BYPASS_MODE: "TRUE" }), true);
});

const invoke = (body) => {
  const req = {
    body,
    ip: "127.0.0.1",
    get: () => "otp-bypass-test",
  };
  let statusCode = 200;
  let payload;
  let error;
  const res = {
    status(code) {
      statusCode = code;
      return this;
    },
    json(data) {
      payload = data;
      return this;
    },
  };
  return sendOtpController(req, res, (err) => {
    error = err;
  }).then(() => ({ statusCode, payload, error }));
};

test("phone login bypass creates, reuses, and tokens the user", async (t) => {
  if (!config.OTP_BYPASS_MODE) {
    t.skip("OTP_BYPASS_MODE is not active in this environment");
    return;
  }

  try {
    await mongoose.connect(config.MONGODB_URL, {
      serverSelectionTimeoutMS: 8000,
    });
  } catch (err) {
    t.skip(`database unavailable: ${err.message}`);
    return;
  }

  const newVendor = `9${String(Date.now()).slice(-9)}`;
  const newCustomer = `8${String(Date.now() + 1).slice(-9)}`;
  const phones = [newVendor, newCustomer];

  try {
    const created = await invoke({ phone: newVendor, role: "vendor" });
    assert.equal(created.error, undefined);
    assert.equal(created.payload.success, true);
    assert.equal(created.payload.data.otpBypass, true);
    assert.equal(created.payload.data.user.phone, newVendor);
    assert.equal(created.payload.data.user.role, "vendor");
    assert.ok(created.payload.data.accessToken);
    assert.ok(created.payload.data.refreshToken);

    const access = verifyAccessToken(created.payload.data.accessToken);
    const refresh = verifyRefreshToken(created.payload.data.refreshToken);
    assert.equal(access.phone, newVendor);
    assert.equal(access.role, "vendor");
    assert.equal(access.userId, created.payload.data.user.id);
    assert.equal(refresh.userId, access.userId);

    const again = await invoke({ phone: newVendor, role: "customer" });
    assert.equal(again.error, undefined);
    assert.equal(again.payload.data.user.id, created.payload.data.user.id);
    assert.equal(again.payload.data.user.role, "vendor");

    const count = await User.countDocuments({ phone: newVendor });
    assert.equal(count, 1);

    const stored = await User.findOne({ phone: newVendor }).lean();
    assert.equal(stored.phone, newVendor);
    assert.equal(stored.role, "vendor");
    assert.ok(Array.isArray(stored.loginHistory) && stored.loginHistory.length >= 2);

    const customer = await invoke({ phone: newCustomer, role: "customer" });
    assert.equal(customer.error, undefined);
    assert.equal(customer.payload.data.user.role, "customer");
    const customerToken = verifyAccessToken(customer.payload.data.accessToken);
    assert.equal(customerToken.role, "customer");

    const invalid = await invoke({ phone: "12345", role: "vendor" });
    assert.ok(invalid.error);
    assert.equal(invalid.error.statusCode, 400);
  } finally {
    await User.deleteMany({ phone: { $in: phones } });
    await mongoose.disconnect();
  }
});
