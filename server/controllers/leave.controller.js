import Joi from "joi";
import LeaveRequest from "../models/LeaveRequest.model.js";
import Subscription from "../models/Subscription.model.js";
import Customer from "../models/Customer.model.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { ApiResponse } from "../class/apiResponseClass.js";
import { ApiError } from "../class/apiErrorClass.js";
import { cutoffRejectionMessage } from "../utils/leaveValidation.js";
import { sendNotification } from "../services/inAppNotification.service.js";
import Notification from "../models/Notification.model.js";
import {
  mealsOverlap,
  waiveOrdersForApprovedLeave,
} from "../services/leaveBilling.service.js";
import { parseUTC } from "../services/dailyOrder.service.js";

async function customerIdFromRequest(req) {
  let customerId = req.user?.customerId;
  if (!customerId && req.user?.phone) {
    const normalized = String(req.user.phone).replace(/\D/g, "").slice(-10);
    const cust = await Customer.findOne({
      phone: new RegExp(normalized + "$"),
      isDeleted: { $ne: true },
    }).select("_id");
    if (cust) customerId = cust._id.toString();
  }
  return customerId || null;
}

/**
 * POST /api/v1/leave/request
 * Customer submits a leave request.
 */
export const requestLeave = asyncHandler(async (req, res) => {
  let customerId = req.user.customerId;
  if (!customerId && req.user.phone) {
    const normalized = String(req.user.phone).replace(/\D/g, "").slice(-10);
    const cust = await Customer.findOne({
      phone: new RegExp(normalized + "$"),
      isDeleted: { $ne: true },
    }).select("_id");
    if (cust) {
      customerId = cust._id.toString();
    }
  }

  if (!customerId && (req.user.role === "vendor" || req.user.role === "admin")) {
    if (req.body.customerId) {
      customerId = req.body.customerId;
    } else {
      const firstCust = await Customer.findOne({
        ownerId: req.user.ownerId || req.user.userId,
        isDeleted: { $ne: true },
      }).select("_id");
      if (firstCust) customerId = firstCust._id.toString();
    }
  }

  if (!customerId) {
    throw new ApiError(400, "Customer profile not found for this account");
  }

  const schema = Joi.object({
    leaveDate: Joi.date().iso().required(),
    mealType: Joi.string().valid("breakfast", "lunch", "dinner", "both", "all").default("all"),
    reason: Joi.string().trim().allow("").optional(),
    notes: Joi.string().trim().allow("").optional(),
    timezoneOffsetMinutes: Joi.number().integer().min(-720).max(840).optional(),
  });

  const { error, value } = schema.validate(req.body, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { leaveDate, mealType, reason, notes } = value;
  const timezoneOffsetMinutes = Number.isFinite(Number(value.timezoneOffsetMinutes))
    ? Number(value.timezoneOffsetMinutes)
    : 330;

  const closedMessage = cutoffRejectionMessage(leaveDate, mealType, timezoneOffsetMinutes);
  if (closedMessage) {
    throw new ApiError(400, closedMessage);
  }

  const startOfDay = parseUTC(leaveDate);
  const endOfDay = new Date(startOfDay);
  endOfDay.setUTCHours(23, 59, 59, 999);

  // Find active subscription covering this date
  let sub = await Subscription.findOne({
    customerId,
    status: "active",
    startDate: { $lte: endOfDay },
    endDate: { $gte: startOfDay },
  });

  // Fallback 1: Any active subscription for this customer
  if (!sub) {
    sub = await Subscription.findOne({
      customerId,
      status: "active",
    }).sort({ endDate: -1 });
  }

  // Fallback 2: Most recent subscription for this customer
  if (!sub) {
    sub = await Subscription.findOne({
      customerId,
    }).sort({ endDate: -1 });
  }

  if (!sub) {
    throw new ApiError(400, "No active subscription found for your account. Please ask your vendor to activate your subscription.");
  }

  const existingRows = await LeaveRequest.find({
    subscriptionId: sub._id,
    leaveDate: { $gte: startOfDay, $lte: endOfDay },
    status: { $in: ["Pending", "Approved"] },
  });
  const existing = existingRows.find((row) => mealsOverlap(row.mealType, mealType));

  if (existing) {
    throw new ApiError(400, `A ${existing.status.toLowerCase()} leave request already exists for this meal.`);
  }

  const leaveRequest = await LeaveRequest.create({
    requestedBy: "Customer",
    customerId,
    vendorId: sub.ownerId,
    subscriptionId: sub._id,
    mealType,
    leaveDate: startOfDay,
    reason: reason || "",
    notes: notes || "",
    status: "Pending",
    timezoneOffsetMinutes,
  });

  // Send notification to the vendor
  try {
    await sendNotification({
      userId: sub.ownerId,
      ownerId: sub.ownerId,
      customerId: customerId,
      type: "leave_request",
      title: "New Leave Request",
      message: `Customer has requested leave for ${new Date(leaveDate).toDateString()} (${mealType}).`,
      data: {
        leaveRequestId: leaveRequest._id,
      },
    });
  } catch (err) {
    console.error("[Notification] Failed to send customer leave request notification:", err.message);
  }

  res.status(201).json(new ApiResponse(201, "Leave request submitted successfully", leaveRequest));
});

const HOLIDAY_MESSAGE =
  "Your meal vendor has declared a holiday for today. No meals will be provided today.";

/**
 * POST /api/v1/leave/vendor/request
 * Vendor declares a kitchen holiday for one date.
 * Only that vendor's subscriptions covering the date are waived, and each
 * customer is notified once.
 */
export const requestVendorLeave = asyncHandler(async (req, res) => {
  const vendorId = req.user.ownerId || req.user.userId;
  if (!vendorId) {
    throw new ApiError(403, "Vendor ID not found in token");
  }

  const schema = Joi.object({
    leaveDate: Joi.date().iso().required(),
    mealType: Joi.string().valid("breakfast", "lunch", "dinner", "both", "all").default("all"),
    reason: Joi.string().trim().allow("").optional(),
    notes: Joi.string().trim().allow("").optional(),
  });

  const { error, value } = schema.validate(req.body, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { leaveDate, reason, notes } = value;
  const mealType = "all";

  const startOfDay = parseUTC(leaveDate);
  const endOfDay = new Date(startOfDay);
  endOfDay.setUTCHours(23, 59, 59, 999);
  const todayStart = parseUTC(new Date());
  if (startOfDay < todayStart) {
    throw new ApiError(400, "Cannot declare holiday for a past date");
  }
  const leaveKey = startOfDay.toISOString().slice(0, 10);

  const [activeSubs, customers] = await Promise.all([
    Subscription.find({
      ownerId: vendorId,
      status: "active",
      startDate: { $lte: endOfDay },
      endDate: { $gte: startOfDay },
    }),
    Customer.find({
      ownerId: vendorId,
      isDeleted: { $ne: true },
    }).select("_id"),
  ]);

  if (customers.length === 0) {
    return res
      .status(200)
      .json(
        new ApiResponse(
          200,
          "No customers found for this vendor. No holiday notifications were sent.",
          []
        )
      );
  }

  const createdRequests = [];

  for (const sub of activeSubs) {
    const existing = await LeaveRequest.findOne({
      vendorId,
      subscriptionId: sub._id,
      requestedBy: "Vendor",
      status: "Approved",
      leaveDate: { $gte: startOfDay, $lte: endOfDay },
    });
    if (existing) continue;

    const leaveRequest = await LeaveRequest.create({
      requestedBy: "Vendor",
      customerId: sub.customerId,
      vendorId,
      subscriptionId: sub._id,
      mealType,
      leaveDate: startOfDay,
      reason: reason || "Vendor Kitchen Holiday",
      notes: notes || "",
      status: "Approved",
      approvedBy: req.user.userId,
      approvedAt: new Date(),
    });
    leaveRequest.waivedAmount = await waiveOrdersForApprovedLeave(leaveRequest);
    await leaveRequest.save();
    createdRequests.push(leaveRequest);
  }

  // Every customer of this vendor gets an approved leave in their history,
  // including customers who have no meal plan covering the date.
  for (const customer of customers) {
    const alreadySaved = await LeaveRequest.findOne({
      vendorId,
      customerId: customer._id,
      requestedBy: "Vendor",
      status: "Approved",
      leaveDate: { $gte: startOfDay, $lte: endOfDay },
    }).select("_id");
    if (alreadySaved) continue;

    const historyLeave = await LeaveRequest.create({
      requestedBy: "Vendor",
      customerId: customer._id,
      vendorId,
      mealType,
      leaveDate: startOfDay,
      reason: reason || "Vendor Kitchen Holiday",
      notes: notes || "",
      status: "Approved",
      approvedBy: req.user.userId,
      approvedAt: new Date(),
      waivedAmount: 0,
    });
    createdRequests.push(historyLeave);
  }

  let notifiedCount = 0;
  for (const customer of customers) {
    const alreadyNotified = await Notification.findOne({
      customerId: customer._id,
      ownerId: vendorId,
      type: "vendor_holiday",
      "data.leaveDate": leaveKey,
    }).select("_id");
    if (alreadyNotified) continue;

    try {
      await sendNotification({
        customerId: customer._id,
        ownerId: vendorId,
        type: "vendor_holiday",
        title: "Vendor holiday",
        message: HOLIDAY_MESSAGE,
        data: {
          leaveDate: leaveKey,
          mealType,
        },
      });
      notifiedCount += 1;
    } catch (err) {
      console.error(
        `[Notification] Failed to send vendor holiday notification to customer ${customer._id}:`,
        err.message
      );
    }
  }

  if (createdRequests.length === 0 && notifiedCount === 0) {
    return res
      .status(200)
      .json(
        new ApiResponse(200, "Holiday is already declared for this date.", {
          alreadyDeclared: true,
          notifiedCount: 0,
        })
      );
  }

  res.status(createdRequests.length > 0 ? 201 : 200).json(
    new ApiResponse(
      createdRequests.length > 0 ? 201 : 200,
      `Vendor holiday declared. ${notifiedCount} customer(s) notified. No meal charges will be added for this date.`,
      {
        subscriptions: createdRequests.length,
        notifiedCount,
      }
    )
  );
});

/**
 * GET /api/v1/leave/customer
 * Fetch leaves for the logged-in customer.
 */
export const getCustomerLeaves = asyncHandler(async (req, res) => {
  let customerId = req.user.customerId;
  if (!customerId && req.user.phone) {
    const normalized = String(req.user.phone).replace(/\D/g, "").slice(-10);
    const cust = await Customer.findOne({
      phone: new RegExp(normalized + "$"),
      isDeleted: { $ne: true },
    }).select("_id");
    if (cust) {
      customerId = cust._id.toString();
    }
  }

  if (!customerId && (req.user.role === "vendor" || req.user.role === "admin")) {
    if (req.query.customerId) {
      customerId = req.query.customerId;
    } else {
      const firstCust = await Customer.findOne({
        ownerId: req.user.ownerId || req.user.userId,
        isDeleted: { $ne: true },
      }).select("_id");
      if (firstCust) customerId = firstCust._id.toString();
    }
  }

  const querySchema = Joi.object({
    page: Joi.number().integer().min(1).default(1),
    limit: Joi.number().integer().min(1).max(100).default(20),
    status: Joi.string().valid("Pending", "Approved", "Rejected", "pending", "approved", "rejected").optional(),
  });

  const { error, value } = querySchema.validate(req.query, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { page, limit } = value;
  const status = value.status
    ? value.status.charAt(0).toUpperCase() + value.status.slice(1).toLowerCase()
    : undefined;
  const skip = (page - 1) * limit;

  const matchQuery = {};
  if (customerId) {
    matchQuery.customerId = customerId;
  } else if (req.user.role === "vendor" || req.user.role === "admin") {
    matchQuery.vendorId = req.user.ownerId || req.user.userId;
  }
  if (status) {
    matchQuery.status = status;
  }

  const [leaves, total] = await Promise.all([
    LeaveRequest.find(matchQuery)
      .sort({ leaveDate: -1, createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate("vendorId", "businessName ownerName phone email")
      .populate("subscriptionId", "startDate endDate deliverySlot totalAmount")
      .lean(),
    LeaveRequest.countDocuments(matchQuery),
  ]);

  res.status(200).json(
    new ApiResponse(200, "Customer leaves fetched successfully", {
      leaves,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    })
  );
});

/**
 * GET /api/v1/leave/vendor
 * Fetch leaves for the logged-in vendor.
 */
export const getVendorLeaves = asyncHandler(async (req, res) => {
  const vendorId = req.user.ownerId;
  if (!vendorId) {
    throw new ApiError(403, "Vendor ID not found in token");
  }

  const querySchema = Joi.object({
    page: Joi.number().integer().min(1).default(1),
    limit: Joi.number().integer().min(1).max(100).default(20),
    status: Joi.string().valid("Pending", "Approved", "Rejected", "pending", "approved", "rejected").optional(),
  });

  const { error, value } = querySchema.validate(req.query, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { page, limit } = value;
  const status = value.status
    ? value.status.charAt(0).toUpperCase() + value.status.slice(1).toLowerCase()
    : undefined;
  const skip = (page - 1) * limit;

  const matchQuery = { vendorId };
  if (status) {
    matchQuery.status = status;
  }

  const [leaves, total] = await Promise.all([
    LeaveRequest.find(matchQuery)
      .sort({ leaveDate: -1, createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate("customerId", "name phone address status")
      .populate("subscriptionId", "startDate endDate deliverySlot totalAmount")
      .lean(),
    LeaveRequest.countDocuments(matchQuery),
  ]);

  res.status(200).json(
    new ApiResponse(200, "Vendor leaves fetched successfully", {
      leaves,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    })
  );
});

/**
 * PUT /api/v1/leave/:id/approve
 * Approves a leave request.
 */
export const approveLeave = asyncHandler(async (req, res) => {
  const { id } = req.params;

  const leaveRequest = await LeaveRequest.findById(id);
  if (!leaveRequest) {
    throw new ApiError(404, "Leave request not found");
  }

  if (leaveRequest.status === "Approved") {
    return res
      .status(200)
      .json(new ApiResponse(200, "Leave request approved successfully", leaveRequest));
  }

  if (leaveRequest.status !== "Pending") {
    throw new ApiError(400, `This leave was already ${leaveRequest.status.toLowerCase()}.`);
  }

  // Authorization check based on who requested it
  if (leaveRequest.requestedBy === "Customer") {
    const vendorId = req.user.ownerId;
    if (req.user.role !== "vendor" && req.user.role !== "admin") {
      throw new ApiError(403, "Access denied. Only vendors can approve customer leave requests.");
    }
    if (leaveRequest.vendorId.toString() !== vendorId?.toString()) {
      throw new ApiError(403, "Access denied. You do not own this customer's subscription.");
    }
  } else if (leaveRequest.requestedBy === "Vendor") {
    const { customerId } = req.user;
    if (req.user.role !== "customer") {
      throw new ApiError(403, "Access denied. Only customers can approve vendor leave requests.");
    }
    if (leaveRequest.customerId.toString() !== customerId?.toString()) {
      throw new ApiError(403, "Access denied. This leave request was not assigned to you.");
    }
  } else {
    throw new ApiError(400, "Invalid requestedBy value on leave request");
  }

  leaveRequest.status = "Approved";
  leaveRequest.approvedBy = req.user.userId;
  leaveRequest.approvedAt = new Date();
  leaveRequest.waivedAmount = await waiveOrdersForApprovedLeave(leaveRequest);
  await leaveRequest.save();

  if (leaveRequest.requestedBy === "Customer") {
    // Notify the Customer
    try {
      await sendNotification({
        customerId: leaveRequest.customerId,
        ownerId: leaveRequest.vendorId,
        type: "leave_approved",
        title: "Leave Approved",
        message: `Your leave request for ${new Date(leaveRequest.leaveDate).toDateString()} (${leaveRequest.mealType}) has been approved. ₹${Number(leaveRequest.waivedAmount || 0).toFixed(0)} will not be charged for this meal.`,
        data: {
          leaveRequestId: leaveRequest._id,
        },
      });
    } catch (err) {
      console.error("[Notification] Failed to send leave approval notification to customer:", err.message);
    }
  } else if (leaveRequest.requestedBy === "Vendor") {
    // Notify the Vendor
    try {
      await sendNotification({
        userId: leaveRequest.vendorId,
        ownerId: leaveRequest.vendorId,
        customerId: leaveRequest.customerId,
        type: "vendor_holiday_approved",
        title: "Holiday Approved by Customer",
        message: `Customer has approved your holiday request for ${new Date(leaveRequest.leaveDate).toDateString()} (${leaveRequest.mealType}).`,
        data: {
          leaveRequestId: leaveRequest._id,
        },
      });
    } catch (err) {
      console.error("[Notification] Failed to send leave approval notification to vendor:", err.message);
    }
  }

  res.status(200).json(new ApiResponse(200, "Leave request approved successfully", leaveRequest));
});

/**
 * PUT /api/v1/leave/:id/reject
 * Rejects a leave request.
 */
export const rejectLeave = asyncHandler(async (req, res) => {
  const { id } = req.params;

  const leaveRequest = await LeaveRequest.findById(id);
  if (!leaveRequest) {
    throw new ApiError(404, "Leave request not found");
  }

  if (leaveRequest.status === "Rejected") {
    return res
      .status(200)
      .json(new ApiResponse(200, "Leave request rejected successfully", leaveRequest));
  }

  if (leaveRequest.status !== "Pending") {
    throw new ApiError(400, `This leave was already ${leaveRequest.status.toLowerCase()}.`);
  }

  // Authorization check based on who requested it
  if (leaveRequest.requestedBy === "Customer") {
    const vendorId = req.user.ownerId;
    if (req.user.role !== "vendor" && req.user.role !== "admin") {
      throw new ApiError(403, "Access denied. Only vendors can reject customer leave requests.");
    }
    if (leaveRequest.vendorId.toString() !== vendorId?.toString()) {
      throw new ApiError(403, "Access denied. You do not own this customer's subscription.");
    }
  } else if (leaveRequest.requestedBy === "Vendor") {
    const { customerId } = req.user;
    if (req.user.role !== "customer") {
      throw new ApiError(403, "Access denied. Only customers can reject vendor leave requests.");
    }
    if (leaveRequest.customerId.toString() !== customerId?.toString()) {
      throw new ApiError(403, "Access denied. This leave request was not assigned to you.");
    }
  } else {
    throw new ApiError(400, "Invalid requestedBy value on leave request");
  }

  leaveRequest.status = "Rejected";
  leaveRequest.approvedBy = req.user.userId;
  leaveRequest.rejectedAt = new Date();
  await leaveRequest.save();

  if (leaveRequest.requestedBy === "Customer") {
    // Notify the Customer
    try {
      await sendNotification({
        customerId: leaveRequest.customerId,
        ownerId: leaveRequest.vendorId,
        type: "leave_rejected",
        title: "Leave Rejected",
        message: `Your leave request for ${new Date(leaveRequest.leaveDate).toDateString()} (${leaveRequest.mealType}) has been rejected.`,
        data: {
          leaveRequestId: leaveRequest._id,
        },
      });
    } catch (err) {
      console.error("[Notification] Failed to send leave rejection notification to customer:", err.message);
    }
  } else if (leaveRequest.requestedBy === "Vendor") {
    // Notify the Vendor
    try {
      await sendNotification({
        userId: leaveRequest.vendorId,
        ownerId: leaveRequest.vendorId,
        customerId: leaveRequest.customerId,
        type: "vendor_holiday_rejected",
        title: "Holiday Rejected by Customer",
        message: `Customer has rejected your holiday request for ${new Date(leaveRequest.leaveDate).toDateString()} (${leaveRequest.mealType}).`,
        data: {
          leaveRequestId: leaveRequest._id,
        },
      });
    } catch (err) {
      console.error("[Notification] Failed to send leave rejection notification to vendor:", err.message);
    }
  }

  res.status(200).json(new ApiResponse(200, "Leave request rejected successfully", leaveRequest));
});

/**
 * GET /api/v1/leave/history
 * Unified endpoint for fetching leave history for the logged-in user.
 */
export const getLeaveHistory = asyncHandler(async (req, res) => {
  const querySchema = Joi.object({
    page: Joi.number().integer().min(1).default(1),
    limit: Joi.number().integer().min(1).max(100).default(20),
    status: Joi.string().valid("Pending", "Approved", "Rejected", "pending", "approved", "rejected").optional(),
  });

  const { error, value } = querySchema.validate(req.query, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { page, limit } = value;
  const status = value.status
    ? value.status.charAt(0).toUpperCase() + value.status.slice(1).toLowerCase()
    : undefined;
  const skip = (page - 1) * limit;

  const matchQuery = {};
  if (status) {
    matchQuery.status = status;
  }

  if (req.user.role === "customer") {
    const customerId = await customerIdFromRequest(req);
    if (!customerId) {
      throw new ApiError(403, "Customer ID not found in token");
    }
    matchQuery.customerId = customerId;
  } else if (req.user.role === "vendor" || req.user.role === "admin") {
    const vendorId = req.user.ownerId;
    if (!vendorId) {
      throw new ApiError(403, "Vendor ID not found in token");
    }
    matchQuery.vendorId = vendorId;
  } else {
    throw new ApiError(403, "Access denied for this role");
  }

  const [leaves, total] = await Promise.all([
    LeaveRequest.find(matchQuery)
      .sort({ leaveDate: -1, createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate("customerId", "name phone address status")
      .populate("vendorId", "businessName ownerName phone email")
      .populate("subscriptionId", "startDate endDate deliverySlot totalAmount")
      .lean(),
    LeaveRequest.countDocuments(matchQuery),
  ]);

  res.status(200).json(
    new ApiResponse(200, "Leave history fetched successfully", {
      leaves,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit),
      },
    })
  );
});

/**
 * GET /api/v1/leave/summary?month=YYYY-MM
 * Monthly leave counts for the logged-in customer or vendor.
 */
export const getLeaveSummary = asyncHandler(async (req, res) => {
  const querySchema = Joi.object({
    month: Joi.string().pattern(/^\d{4}-\d{2}$/).optional(),
    timezoneOffsetMinutes: Joi.number().integer().min(-720).max(840).optional(),
  });
  const { error, value } = querySchema.validate(req.query, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const offset = Number.isFinite(Number(value.timezoneOffsetMinutes))
    ? Number(value.timezoneOffsetMinutes)
    : 330;
  const shifted = new Date(Date.now() + offset * 60 * 1000);
  const month =
    value.month ||
    `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, "0")}`;
  const [year, mon] = month.split("-").map(Number);
  const start = new Date(Date.UTC(year, mon - 1, 1));
  const end = new Date(Date.UTC(year, mon, 0, 23, 59, 59, 999));

  const matchQuery = { leaveDate: { $gte: start, $lte: end } };
  if (req.user.role === "customer") {
    const customerId = await customerIdFromRequest(req);
    if (!customerId) throw new ApiError(403, "Customer ID not found in token");
    matchQuery.customerId = customerId;
  } else if (req.user.role === "vendor" || req.user.role === "admin") {
    const vendorId = req.user.ownerId || req.user.userId;
    if (!vendorId) throw new ApiError(403, "Vendor ID not found in token");
    matchQuery.vendorId = vendorId;
  } else {
    throw new ApiError(403, "Access denied for this role");
  }

  const leaves = await LeaveRequest.find(matchQuery).lean();
  const tally = { Pending: 0, Approved: 0, Rejected: 0 };
  const byMeal = { breakfast: 0, lunch: 0, dinner: 0 };
  let waivedAmount = 0;
  for (const leave of leaves) {
    tally[leave.status] = (tally[leave.status] || 0) + 1;
    if (leave.status === "Approved") {
      waivedAmount += Number(leave.waivedAmount) || 0;
      const meals =
        leave.mealType === "all" || leave.mealType === "both"
          ? ["breakfast", "lunch", "dinner"]
          : [leave.mealType];
      for (const meal of meals) {
        if (byMeal[meal] != null) byMeal[meal] += 1;
      }
    }
  }

  res.status(200).json(
    new ApiResponse(200, "Leave summary fetched", {
      month,
      total: leaves.length,
      pending: tally.Pending,
      approved: tally.Approved,
      rejected: tally.Rejected,
      byMeal,
      waivedAmount: Math.round(waivedAmount * 100) / 100,
    })
  );
});
