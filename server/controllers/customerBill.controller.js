import Joi from "joi";
import PDFDocument from "pdfkit";
import Customer from "../models/Customer.model.js";
import User from "../models/User.model.js";
import DailyOrder from "../models/DailyOrder.model.js";
import LeaveRequest from "../models/LeaveRequest.model.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { ApiResponse } from "../class/apiResponseClass.js";
import { ApiError } from "../class/apiErrorClass.js";
import { summarizeMonthlyBill } from "../services/leaveBilling.service.js";

async function customerIdFromRequest(req) {
  let customerId = req.user?.customerId;
  if (!customerId && req.user?.phone) {
    const normalized = String(req.user.phone).replace(/\D/g, "").slice(-10);
    const cust = await Customer.findOne({
      phone: new RegExp(`${normalized}$`),
      isDeleted: { $ne: true },
    }).select("_id");
    if (cust) customerId = cust._id.toString();
  }
  if (!customerId && (req.user?.role === "vendor" || req.user?.role === "admin")) {
    const firstCust = await Customer.findOne({
      ownerId: req.user.ownerId || req.user.userId,
      isDeleted: { $ne: true },
    }).select("_id");
    if (firstCust) customerId = firstCust._id.toString();
  }
  return customerId || null;
}

function monthRange(month) {
  const [year, mon] = month.split("-").map(Number);
  const start = new Date(Date.UTC(year, mon - 1, 1));
  const end = new Date(Date.UTC(year, mon, 0, 23, 59, 59, 999));
  return { start, end };
}

async function loadMonthlyBill(req) {
  const schema = Joi.object({
    month: Joi.string().pattern(/^\d{4}-\d{2}$/).optional(),
    timezoneOffsetMinutes: Joi.number().integer().min(-720).max(840).optional(),
  });
  const { error, value } = schema.validate(req.query, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const customerId = await customerIdFromRequest(req);
  if (!customerId) throw new ApiError(404, "Customer profile not found");

  const offset = Number.isFinite(Number(value.timezoneOffsetMinutes))
    ? Number(value.timezoneOffsetMinutes)
    : 330;
  const shifted = new Date(Date.now() + offset * 60 * 1000);
  const month =
    value.month ||
    `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, "0")}`;
  const { start, end } = monthRange(month);

  const customer = await Customer.findOne({
    _id: customerId,
    isDeleted: { $ne: true },
  }).lean();
  if (!customer) throw new ApiError(404, "Customer profile not found");

  const [orders, leaves, vendor] = await Promise.all([
    DailyOrder.find({
      customerId,
      orderDate: { $gte: start, $lte: end },
    })
      .sort({ orderDate: 1 })
      .lean(),
    LeaveRequest.find({
      customerId,
      leaveDate: { $gte: start, $lte: end },
    })
      .sort({ leaveDate: 1 })
      .lean(),
    User.findById(customer.ownerId).select("businessName ownerName phone").lean(),
  ]);

  const summary = summarizeMonthlyBill({ orders, leaves });
  return {
    month,
    customer: {
      id: customer._id,
      name: customer.name || "",
      phone: customer.phone || "",
    },
    vendor: {
      businessName: vendor?.businessName || vendor?.ownerName || "Tiffin service",
      phone: vendor?.phone || "",
    },
    ...summary,
    leaveCounts: {
      pending: leaves.filter((leave) => leave.status === "Pending").length,
      approved: leaves.filter((leave) => leave.status === "Approved").length,
      rejected: leaves.filter((leave) => leave.status === "Rejected").length,
    },
  };
}

export const getMyMonthlyBill = asyncHandler(async (req, res) => {
  const bill = await loadMonthlyBill(req);
  res.status(200).json(new ApiResponse(200, "Monthly bill fetched", bill));
});

function renderBillPdf(bill) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 48, size: "A4" });
    const chunks = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.fontSize(20).text(bill.vendor.businessName, { align: "center" });
    doc.moveDown(0.3);
    doc.fontSize(14).text(`Monthly meal bill — ${bill.month}`, { align: "center" });
    doc.moveDown();
    doc.fontSize(11).text(`Customer: ${bill.customer.name || "—"}`);
    if (bill.customer.phone) doc.text(`Phone: ${bill.customer.phone}`);
    doc.moveDown();

    doc.fontSize(10);
    doc.text("Date", 48, doc.y, { continued: true, width: 110 });
    doc.text("Meal", 160, doc.y, { continued: true, width: 160 });
    doc.text("Amount", 400, doc.y, { width: 120, align: "right" });
    doc.moveDown(0.4);
    doc.moveTo(48, doc.y).lineTo(547, doc.y).stroke();
    doc.moveDown(0.4);

    const rows = bill.lines.length
      ? bill.lines
      : [{ date: null, description: "No meals in this month", amount: 0, excluded: 0, kind: "meal" }];

    for (const line of rows) {
      const date = line.date
        ? new Date(line.date).toISOString().slice(0, 10)
        : "—";
      const label =
        line.kind === "leave"
          ? `${line.description} (₹${Number(line.excluded || 0).toFixed(0)} excluded)`
          : line.description;
      const amount =
        line.kind === "leave" ? "₹0" : `₹${Number(line.amount || 0).toFixed(0)}`;
      const y = doc.y;
      doc.text(date, 48, y, { width: 110 });
      doc.text(label, 160, y, { width: 230 });
      doc.text(amount, 400, y, { width: 120, align: "right" });
      doc.moveDown(0.8);
      if (doc.y > 740) doc.addPage();
    }

    doc.moveDown();
    doc.moveTo(48, doc.y).lineTo(547, doc.y).stroke();
    doc.moveDown(0.6);
    doc.fontSize(11);
    doc.text(`Meals charged: ₹${Number(bill.chargedAmount).toFixed(0)}`);
    doc.text(`Approved leave credit: ₹${Number(bill.leaveCredit).toFixed(0)}`);
    doc.fontSize(13).text(`Amount due: ₹${Number(bill.netAmount).toFixed(0)}`, {
      underline: true,
    });
    doc.moveDown();
    doc.fontSize(9).fillColor("#555").text(
      "Approved leave meals are not charged. Pending and rejected requests stay on the bill until a leave is approved."
    );
    doc.end();
  });
}

export const downloadMyMonthlyBill = asyncHandler(async (req, res) => {
  const bill = await loadMonthlyBill(req);
  const pdf = await renderBillPdf(bill);
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader(
    "Content-Disposition",
    `attachment; filename="meal-bill-${bill.month}.pdf"`
  );
  res.send(pdf);
});
