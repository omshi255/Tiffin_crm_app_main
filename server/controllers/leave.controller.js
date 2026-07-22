import Joi from "joi";
import mongoose from "mongoose";
import LeaveRequest from "../models/LeaveRequest.model.js";
import Subscription from "../models/Subscription.model.js";
import Customer from "../models/Customer.model.js";
import DailyOrder from "../models/DailyOrder.model.js";
import { asyncHandler } from "../utils/asyncHandler.js";
import { ApiResponse } from "../class/apiResponseClass.js";
import { ApiError } from "../class/apiErrorClass.js";
import { isCutoffExceeded } from "../utils/leaveValidation.js";
import { sendNotification } from "../services/inAppNotification.service.js";

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
  });

  const { error, value } = schema.validate(req.body, { stripUnknown: true });
  if (error) {
    throw new ApiError(400, error.details.map((d) => d.message).join("; "));
  }

  const { leaveDate, mealType, reason, notes } = value;

  const startOfDay = new Date(leaveDate);
  startOfDay.setHours(0, 0, 0, 0);

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  if (startOfDay < todayStart) {
    throw new ApiError(400, "Cannot request leave for a past date");
  }

  if (isCutoffExceeded(leaveDate, mealType)) {
    throw new ApiError(400, "Leave request is closed because meal preparation has already started.");
  }

  const endOfDay = new Date(leaveDate);
  endOfDay.setHours(23, 59, 59, 999);

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

  // Check if a leave request already exists for this date and subscription
  const existing = await LeaveRequest.findOne({
    subscriptionId: sub._id,
    leaveDate: { $gte: startOfDay, $lte: endOfDay },
  });

  if (existing) {
    throw new ApiError(400, `A leave request already exists for this date in status: ${existing.status}`);
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

/**
 * POST /api/v1/leave/vendor/request
 * Vendor submits a leave request for all active customers.
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

  const { leaveDate, mealType, reason, notes } = value;

  const startOfDay = new Date(leaveDate);
  startOfDay.setHours(0, 0, 0, 0);

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  if (startOfDay < todayStart) {
    throw new ApiError(400, "Cannot declare holiday for a past date");
  }

  const endOfDay = new Date(leaveDate);
  endOfDay.setHours(23, 59, 59, 999);

  // Find all active subscriptions of vendor's customers covering the leave date
  let activeSubs = await Subscription.find({
    ownerId: vendorId,
    status: "active",
    startDate: { $lte: endOfDay },
    endDate: { $gte: startOfDay },
  });

  // Fallback: If no date-restricted active subs, find all active subscriptions for this vendor
  if (activeSubs.length === 0) {
    activeSubs = await Subscription.find({
      ownerId: vendorId,
      status: "active",
    });
  }

  if (activeSubs.length === 0) {
    return res
      .status(200)
      .json(
        new ApiResponse(
          200,
          "No active customer subscriptions found. No holiday orders created.",
          []
        )
      );
  }

  const createdRequests = [];

  for (const sub of activeSubs) {
    let leaveRequest = await LeaveRequest.findOne({
      subscriptionId: sub._id,
      leaveDate: { $gte: startOfDay, $lte: endOfDay },
      requestedBy: "Vendor",
    });

    if (!leaveRequest) {
      leaveRequest = await LeaveRequest.create({
        requestedBy: "Vendor",
        customerId: sub.customerId,
        vendorId: vendorId,
        subscriptionId: sub._id,
        mealType,
        leaveDate: startOfDay,
        reason: reason || "Vendor Kitchen Holiday",
        notes: notes || "",
        status: "Approved",
        approvedBy: req.user.userId,
        approvedAt: new Date(),
      });
    } else {
      leaveRequest.status = "Approved";
      leaveRequest.approvedBy = req.user.userId;
      leaveRequest.approvedAt = new Date();
      await leaveRequest.save();
    }

    // Immediately mark existing pending daily orders as skipped for this date & meal
    const pendingOrders = await DailyOrder.find({
      subscriptionId: sub._id,
      orderDate: { $gte: startOfDay, $lte: endOfDay },
      status: "pending",
    });

    const isMealSkippedByLeave = (meal) => {
      if (mealType === "all" || mealType === "both") return true;
      if (mealType === "breakfast" && (meal === "breakfast" || meal === "early_morning"))
        return true;
      if (mealType === "lunch" && meal === "lunch") return true;
      if (mealType === "dinner" && meal === "dinner") return true;
      return false;
    };

    for (const order of pendingOrders) {
      if (isMealSkippedByLeave(order.mealType)) {
        order.status = "skipped";
        order.cancellationReason = "Vendor Holiday";
        order.cancelledAt = new Date();
        await order.save();
      }
    }

    // Send notification to customer
    try {
      await sendNotification({
        customerId: sub.customerId,
        ownerId: vendorId,
        type: "vendor_holiday",
        title: "Vendor Kitchen Holiday Declared",
        message: `Our kitchen will be closed on ${new Date(
          leaveDate
        ).toDateString()} (${mealType}). Subscription amount for this day will not be charged (₹0).`,
        data: {
          leaveDate,
          mealType,
        },
      });
    } catch (err) {
      console.error(
        `[Notification] Failed to send vendor holiday notification to customer ${sub.customerId}:`,
        err.message
      );
    }

    createdRequests.push(leaveRequest);
  }

  res
    .status(201)
    .json(
      new ApiResponse(
        201,
        `Vendor holiday declared for ${createdRequests.length} customer subscription(s). No subscription charges will be added for this date.`,
        createdRequests
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

  if (leaveRequest.status !== "Pending") {
    throw new ApiError(400, `Leave request is already ${leaveRequest.status.toLowerCase()}`);
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
  await leaveRequest.save();

  // Find and update matching pending orders to skipped status
  const startOfDay = new Date(leaveRequest.leaveDate);
  startOfDay.setHours(0, 0, 0, 0);
  const endOfDay = new Date(leaveRequest.leaveDate);
  endOfDay.setHours(23, 59, 59, 999);

  const pendingOrders = await DailyOrder.find({
    subscriptionId: leaveRequest.subscriptionId,
    orderDate: { $gte: startOfDay, $lte: endOfDay },
    status: "pending",
  });

  const isMealSkippedByLeave = (meal) => {
    if (leaveRequest.mealType === "all" || leaveRequest.mealType === "both") {
      return true;
    }
    if (leaveRequest.mealType === "breakfast" && (meal === "breakfast" || meal === "early_morning")) {
      return true;
    }
    if (leaveRequest.mealType === "lunch" && meal === "lunch") {
      return true;
    }
    if (leaveRequest.mealType === "dinner" && meal === "dinner") {
      return true;
    }
    return false;
  };

  for (const order of pendingOrders) {
    if (isMealSkippedByLeave(order.mealType)) {
      order.status = "skipped";
      order.cancellationReason = "Leave Approved";
      order.cancelledAt = new Date();
      await order.save();
    }
  }

  if (leaveRequest.requestedBy === "Customer") {
    // Notify the Customer
    try {
      await sendNotification({
        customerId: leaveRequest.customerId,
        ownerId: leaveRequest.vendorId,
        type: "leave_approved",
        title: "Leave Approved",
        message: `Your leave request for ${new Date(leaveRequest.leaveDate).toDateString()} (${leaveRequest.mealType}) has been approved.`,
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

  if (leaveRequest.status !== "Pending") {
    throw new ApiError(400, `Leave request is already ${leaveRequest.status.toLowerCase()}`);
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
    const { customerId } = req.user;
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
