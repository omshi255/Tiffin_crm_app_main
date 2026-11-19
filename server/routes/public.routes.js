import { Router } from "express";
import mongoose from "mongoose";
import Invoice from "../models/Invoice.model.js";
import Customer from "../models/Customer.model.js";
import User from "../models/User.model.js";
import { ApiError } from "../class/apiErrorClass.js";
import { asyncHandler } from "../utils/asyncHandler.js";

const router = Router();

router.get("/health", (req, res) => {
  res.json({ status: "ok", version: "4.0" });
});

router.get(
  "/invoice/:shareToken",
  asyncHandler(async (req, res) => {
    const { shareToken } = req.params;
    const invoice = await Invoice.findOne({ shareToken })
      .select("-shareToken")
      .populate("customerId", "name phone")
      .populate("ownerId", "businessName ownerName")
      .lean();
    if (!invoice) throw new ApiError(404, "Invoice not found");
    if (
      invoice.shareTokenExpiresAt &&
      invoice.shareTokenExpiresAt.getTime() < Date.now()
    ) {
      throw new ApiError(410, "Share link expired");
    }

    const customer = invoice.customerId || {};
    const vendor = invoice.ownerId || {};
    const items = Array.isArray(invoice.lineItems) ? invoice.lineItems : [];
    const money = (n) => `Rs.${Number(n || 0).toFixed(0)}`;
    const day = (d) => {
      if (!d) return "";
      return new Date(d).toLocaleDateString("en-IN", {
        day: "numeric",
        month: "short",
        year: "numeric",
        timeZone: "UTC",
      });
    };
    const esc = (s) =>
      String(s ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    const rows = items
      .map(
        (li) => `<tr>
          <td>${esc(li.description)}</td>
          <td>${esc(li.quantity ?? 1)}</td>
          <td>${money(li.amount)}</td>
        </tr>`
      )
      .join("");

    res.type("html").send(`<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(invoice.invoiceNumber || "Invoice")}</title>
<style>
  body{font-family:Segoe UI,sans-serif;background:#f6f4ff;color:#1a0e45;margin:0;padding:24px}
  .card{max-width:640px;margin:0 auto;background:#fff;border:1px solid #e4dff7;border-radius:16px;padding:24px}
  h1{font-size:20px;margin:0 0 4px} .muted{color:#6e628f;font-size:13px}
  table{width:100%;border-collapse:collapse;margin-top:16px}
  td,th{text-align:left;padding:8px 0;border-bottom:1px solid #eeeaf8;font-size:14px}
  .total{font-size:18px;font-weight:700;margin-top:16px}
</style></head><body><div class="card">
  <h1>${esc(vendor.businessName || vendor.ownerName || "Meal invoice")}</h1>
  <div class="muted">${esc(invoice.invoiceNumber || "")}</div>
  <p><strong>${esc(customer.name || "Customer")}</strong><br>
  <span class="muted">${esc(customer.phone || "")}</span></p>
  <div class="muted">${day(invoice.billingStart)} – ${day(invoice.billingEnd)}</div>
  <table><thead><tr><th>Meal</th><th>Qty</th><th>Amount</th></tr></thead>
  <tbody>${rows || "<tr><td colspan='3'>No line items</td></tr>"}</tbody></table>
  <div class="total">Total ${money(invoice.netAmount)}</div>
  <p class="muted">Status: ${esc(invoice.isVoid ? "voided" : invoice.paymentStatus || "unpaid")}</p>
</div></body></html>`);
  })
);

/**
 * Public: vendor portal announcement for imeals.in / marketing pages (no auth).
 * GET /api/v1/public/vendor/:ownerId/portal-announcement
 */
router.get(
  "/vendor/:ownerId/portal-announcement",
  asyncHandler(async (req, res) => {
    const { ownerId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(ownerId)) {
      throw new ApiError(400, "Invalid vendor id");
    }
    const user = await User.findById(ownerId)
      .select(
        "role businessName ownerName settings.portalAnnouncementText settings.portalAnnouncementUpdatedAt"
      )
      .lean();
    if (!user || user.role !== "vendor") {
      throw new ApiError(404, "Vendor not found");
    }
    res.json({
      businessName: (user.businessName || "").trim(),
      ownerName: (user.ownerName || "").trim(),
      text: (user.settings?.portalAnnouncementText ?? "").trim(),
      updatedAt: user.settings?.portalAnnouncementUpdatedAt ?? null,
    });
  })
);

router.get(
  "/customer-report/:token",
  asyncHandler(async (req, res) => {
    const { token } = req.params;
    const customer = await Customer.findOne({ reportToken: token })
      .select("name phone address area balance totalDue tags notes")
      .lean();
    if (!customer) throw new ApiError(404, "Customer not found");
    if (
      customer.reportTokenExpiresAt &&
      customer.reportTokenExpiresAt.getTime() < Date.now()
    ) {
      throw new ApiError(410, "TOKEN_EXPIRED");
    }
    res.json(customer);
  })
);

export default router;

