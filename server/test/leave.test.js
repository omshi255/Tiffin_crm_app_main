import test from "node:test";
import assert from "node:assert/strict";
import mongoose from "mongoose";
import LeaveRequest from "../models/LeaveRequest.model.js";
import Notification from "../models/Notification.model.js";

test("LeaveRequest Model: validation constraints", () => {
  // 1. Missing fields should fail validation
  const reqEmpty = new LeaveRequest({});
  const err = reqEmpty.validateSync();
  assert.ok(err, "Empty document should fail validation");
  assert.ok(err.errors.requestedBy, "requestedBy is required");
  assert.ok(err.errors.customerId, "customerId is required");
  assert.ok(err.errors.vendorId, "vendorId is required");
  assert.ok(err.errors.subscriptionId, "subscriptionId is required");
  assert.ok(err.errors.leaveDate, "leaveDate is required");

  // 2. Invalid requestedBy value should fail
  const reqInvalidRequestedBy = new LeaveRequest({
    requestedBy: "OtherUser",
    customerId: new mongoose.Types.ObjectId(),
    vendorId: new mongoose.Types.ObjectId(),
    subscriptionId: new mongoose.Types.ObjectId(),
    leaveDate: new Date(),
  });
  const err2 = reqInvalidRequestedBy.validateSync();
  assert.ok(err2, "Invalid requestedBy should fail");
  assert.ok(err2.errors.requestedBy, "requestedBy must be Customer or Vendor");

  // 3. Invalid status value should fail
  const reqInvalidStatus = new LeaveRequest({
    requestedBy: "Customer",
    customerId: new mongoose.Types.ObjectId(),
    vendorId: new mongoose.Types.ObjectId(),
    subscriptionId: new mongoose.Types.ObjectId(),
    leaveDate: new Date(),
    status: "UnknownStatus",
  });
  const err3 = reqInvalidStatus.validateSync();
  assert.ok(err3, "Invalid status should fail");
  assert.ok(err3.errors.status, "status must be Pending, Approved, or Rejected");

  // 4. Invalid mealType value should fail
  const reqInvalidMealType = new LeaveRequest({
    requestedBy: "Customer",
    customerId: new mongoose.Types.ObjectId(),
    vendorId: new mongoose.Types.ObjectId(),
    subscriptionId: new mongoose.Types.ObjectId(),
    leaveDate: new Date(),
    mealType: "midnight_snack",
  });
  const errMealType = reqInvalidMealType.validateSync();
  assert.ok(errMealType, "Invalid mealType should fail");
  assert.ok(errMealType.errors.mealType, "mealType must be breakfast, lunch, dinner, both, or all");

  // 5. Valid document should pass validation successfully
  const validRequest = new LeaveRequest({
    requestedBy: "Customer",
    customerId: new mongoose.Types.ObjectId(),
    vendorId: new mongoose.Types.ObjectId(),
    subscriptionId: new mongoose.Types.ObjectId(),
    leaveDate: new Date(),
    mealType: "lunch",
    reason: "Going out of town",
    status: "Pending",
  });
  const err4 = validRequest.validateSync();
  assert.equal(err4, undefined, "Valid document should pass validation");
});

import { isCutoffExceeded } from "../utils/leaveValidation.js";

test("leaveValidation: isCutoffExceeded at 11:00 AM IST", () => {
  const originalDate = global.Date;
  // Mock current time to 2026-07-21T11:00:00 local time in Asia/Kolkata
  // 11:00 AM IST = 05:30 AM UTC
  const mockNow = new originalDate("2026-07-21T05:30:00Z");

  global.Date = class extends originalDate {
    constructor(...args) {
      if (args.length === 0) return new originalDate(mockNow);
      return new originalDate(...args);
    }
    static now() {
      return mockNow.getTime();
    }
  };

  try {
    // Today's leaves
    assert.equal(isCutoffExceeded("2026-07-21", "breakfast"), true, "Breakfast today at 11:00 AM is exceeded");
    assert.equal(isCutoffExceeded("2026-07-21", "lunch"), true, "Lunch today at 11:00 AM is exceeded");
    assert.equal(isCutoffExceeded("2026-07-21", "dinner"), false, "Dinner today at 11:00 AM is NOT exceeded");
    assert.equal(isCutoffExceeded("2026-07-21", "all"), true, "All meals today at 11:00 AM is exceeded (because breakfast is exceeded)");

    // Future leaves
    assert.equal(isCutoffExceeded("2026-07-22", "breakfast"), false, "Tomorrow's breakfast is NOT exceeded");
    assert.equal(isCutoffExceeded("2026-07-22", "all"), false, "Tomorrow's all meals are NOT exceeded");

    // Past leaves
    assert.equal(isCutoffExceeded("2026-07-20", "dinner"), true, "Yesterday's dinner is exceeded");
  } finally {
    global.Date = originalDate;
  }
});

test("leaveValidation: isCutoffExceeded at 8:00 PM IST", () => {
  const originalDate = global.Date;
  // Mock current time to 2026-07-21T20:00:00 local time in Asia/Kolkata
  // 8:00 PM IST = 14:30 UTC
  const mockNow = new originalDate("2026-07-21T14:30:00Z");

  global.Date = class extends originalDate {
    constructor(...args) {
      if (args.length === 0) return new originalDate(mockNow);
      return new originalDate(...args);
    }
    static now() {
      return mockNow.getTime();
    }
  };

  try {
    assert.equal(isCutoffExceeded("2026-07-21", "breakfast"), true, "Breakfast today at 8:00 PM is exceeded");
    assert.equal(isCutoffExceeded("2026-07-21", "lunch"), true, "Lunch today at 8:00 PM is exceeded");
    assert.equal(isCutoffExceeded("2026-07-21", "dinner"), true, "Dinner today at 8:00 PM is exceeded");
  } finally {
    global.Date = originalDate;
  }
});

import { generateDailyOrdersForDate } from "../services/dailyOrder.service.js";
import Subscription from "../models/Subscription.model.js";
import Customer from "../models/Customer.model.js";
import MealPlan from "../models/Plan.model.js";
import DailyOrder from "../models/DailyOrder.model.js";
import { approveLeave } from "../controllers/leave.controller.js";

test("Integration: generateDailyOrdersForDate skips orders if leave is approved", async () => {
  const originalCustomerFind = Customer.find;
  const originalSubscriptionFind = Subscription.find;
  const originalMealPlanFind = MealPlan.find;
  const originalDailyOrderFind = DailyOrder.find;
  const originalDailyOrderInsertMany = DailyOrder.insertMany;
  const originalLeaveRequestFind = LeaveRequest.find;

  const mockCustomerId = new mongoose.Types.ObjectId();
  const mockSubId = new mongoose.Types.ObjectId();
  const mockPlanId = new mongoose.Types.ObjectId();
  const mockOwnerId = new mongoose.Types.ObjectId();

  Customer.find = () => ({
    distinct: async () => [mockCustomerId],
  });

  Subscription.find = () => {
    return {
      lean: async () => [
        {
          _id: mockSubId,
          ownerId: mockOwnerId,
          customerId: mockCustomerId,
          planId: mockPlanId,
          startDate: new Date("2026-07-21T00:00:00Z"),
          endDate: new Date("2026-07-21T23:59:59Z"),
          status: "active",
          deliveryDays: [2],
          deliverySlot: "morning",
        },
      ],
    };
  };

  DailyOrder.find = () => ({
    select: () => ({
      lean: async () => [],
    }),
  });

  MealPlan.find = () => ({
    lean: async () => [
      {
        _id: mockPlanId,
        isActive: true,
        price: 100,
        mealSlots: [{ slot: "lunch", items: [] }],
      },
    ],
  });

  LeaveRequest.find = () => ({
    lean: async () => [
      {
        subscriptionId: mockSubId,
        leaveDate: new Date("2026-07-21T00:00:00Z"),
        mealType: "lunch",
        status: "Approved",
      },
    ],
  });

  let insertedOrders = [];
  DailyOrder.insertMany = async (orders) => {
    insertedOrders = orders;
    return orders;
  };

  try {
    const res = await generateDailyOrdersForDate(mockOwnerId, new Date("2026-07-21T00:00:00Z"));
    assert.equal(res.generatedCount, 1);
    assert.equal(insertedOrders.length, 1);
    assert.equal(insertedOrders[0].status, "skipped");
    assert.equal(insertedOrders[0].cancellationReason, "Leave Approved");
  } finally {
    Customer.find = originalCustomerFind;
    Subscription.find = originalSubscriptionFind;
    MealPlan.find = originalMealPlanFind;
    DailyOrder.find = originalDailyOrderFind;
    DailyOrder.insertMany = originalDailyOrderInsertMany;
    LeaveRequest.find = originalLeaveRequestFind;
  }
});

test("Integration: approveLeave transitions pending daily orders to skipped", async () => {
  const originalLeaveRequestFindById = LeaveRequest.findById;
  const originalDailyOrderFind = DailyOrder.find;
  const originalNotificationCreate = Notification.create;

  Notification.create = async () => ({});

  const mockSubId = new mongoose.Types.ObjectId();
  const mockLeaveId = new mongoose.Types.ObjectId();
  const mockCustomerId = new mongoose.Types.ObjectId();
  const mockVendorId = new mongoose.Types.ObjectId();

  const mockLeaveDoc = {
    _id: mockLeaveId,
    requestedBy: "Customer",
    status: "Pending",
    leaveDate: new Date("2026-07-21T00:00:00Z"),
    subscriptionId: mockSubId,
    customerId: mockCustomerId,
    vendorId: mockVendorId,
    mealType: "lunch",
    save: async function () {
      this.status = "Approved";
      return this;
    },
  };

  LeaveRequest.findById = async () => mockLeaveDoc;

  let orderSaved = false;
  const mockOrderDoc = {
    subscriptionId: mockSubId,
    orderDate: new Date("2026-07-21T00:00:00Z"),
    mealType: "lunch",
    status: "pending",
    save: async function () {
      orderSaved = true;
      assert.equal(this.status, "skipped");
      assert.equal(this.cancellationReason, "Leave Approved");
      return this;
    },
  };

  DailyOrder.find = async () => [mockOrderDoc];

  try {
    const req = {
      params: { id: mockLeaveId.toString() },
      user: {
        userId: new mongoose.Types.ObjectId().toString(),
        role: "vendor",
        ownerId: mockVendorId.toString(),
      },
    };

    let responseStatus = null;
    let responseData = null;
    const res = {
      status: function (code) {
        responseStatus = code;
        return this;
      },
      json: function (data) {
        responseData = data;
        return this;
      },
    };

    await approveLeave(req, res);

    assert.equal(responseStatus, 200);
    assert.equal(mockLeaveDoc.status, "Approved");
    assert.ok(orderSaved);
  } finally {
    LeaveRequest.findById = originalLeaveRequestFindById;
    DailyOrder.find = originalDailyOrderFind;
    Notification.create = originalNotificationCreate;
  }
});

// Integration notification tests

test("Integration: approveLeave triggers notifications for Customer requested leaves", async () => {
  const originalLeaveRequestFindById = LeaveRequest.findById;
  const originalDailyOrderFind = DailyOrder.find;
  const originalNotificationCreate = Notification.create;

  const mockSubId = new mongoose.Types.ObjectId();
  const mockLeaveId = new mongoose.Types.ObjectId();
  const mockCustomerId = new mongoose.Types.ObjectId();
  const mockVendorId = new mongoose.Types.ObjectId();

  const mockLeaveDoc = {
    _id: mockLeaveId,
    requestedBy: "Customer",
    status: "Pending",
    leaveDate: new Date("2026-07-21T00:00:00Z"),
    subscriptionId: mockSubId,
    customerId: mockCustomerId,
    vendorId: mockVendorId,
    mealType: "lunch",
    save: async function () {
      this.status = "Approved";
      return this;
    },
  };

  LeaveRequest.findById = async () => mockLeaveDoc;
  DailyOrder.find = async () => [];

  let notificationDoc = null;
  Notification.create = async (doc) => {
    notificationDoc = doc;
    return doc;
  };

  try {
    const req = {
      params: { id: mockLeaveId.toString() },
      user: {
        userId: new mongoose.Types.ObjectId().toString(),
        role: "vendor",
        ownerId: mockVendorId.toString(),
      },
    };

    const res = {
      status: function () { return this; },
      json: function () { return this; },
    };

    await approveLeave(req, res);

    assert.ok(notificationDoc, "Notification should be created");
    assert.equal(notificationDoc.customerId.toString(), mockCustomerId.toString());
    assert.equal(notificationDoc.type, "leave_approved");
    assert.equal(notificationDoc.title, "Leave Approved");
  } finally {
    LeaveRequest.findById = originalLeaveRequestFindById;
    DailyOrder.find = originalDailyOrderFind;
    Notification.create = originalNotificationCreate;
  }
});

// Import controllers to test them directly
import { requestLeave, rejectLeave } from "../controllers/leave.controller.js";

test("Integration: requestLeave throws ApiError when date is in the past", async () => {
  const req = {
    user: { customerId: new mongoose.Types.ObjectId().toString() },
    body: {
      leaveDate: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(), // yesterday
      mealType: "lunch",
      reason: "Went to the past",
    },
  };

  const res = {};
  let errorThrown = null;
  const next = (err) => {
    errorThrown = err;
  };

  await requestLeave(req, res, next);
  assert.ok(errorThrown, "Should have passed error to next");
  assert.equal(errorThrown.statusCode, 400);
  assert.equal(errorThrown.message, "Cannot request leave for a past date");
});

test("Integration: requestLeave throws ApiError when duplicate request exists", async () => {
  const originalSubscriptionFindOne = Subscription.findOne;
  const originalLeaveRequestFind = LeaveRequest.find;

  const mockSubId = new mongoose.Types.ObjectId();
  const mockCustomerId = new mongoose.Types.ObjectId();
  const mockVendorId = new mongoose.Types.ObjectId();

  Subscription.findOne = async () => ({
    _id: mockSubId,
    customerId: mockCustomerId,
    ownerId: mockVendorId,
    status: "active",
  });

  LeaveRequest.find = async () => ([
    {
      _id: new mongoose.Types.ObjectId(),
      status: "Pending",
      mealType: "lunch",
    },
  ]);

  const req = {
    user: { customerId: mockCustomerId.toString() },
    body: {
      leaveDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      mealType: "lunch",
      reason: "Already submitted",
    },
  };

  const res = {};
  let errorThrown = null;
  const next = (err) => {
    errorThrown = err;
  };

  try {
    await requestLeave(req, res, next);
    assert.ok(errorThrown, "Should have passed duplicate error to next");
    assert.equal(errorThrown.statusCode, 400);
    assert.match(errorThrown.message, /leave request already exists/);
  } finally {
    Subscription.findOne = originalSubscriptionFindOne;
    LeaveRequest.find = originalLeaveRequestFind;
  }
});

test("Integration: rejectLeave works and notifies customer", async () => {
  const originalLeaveRequestFindById = LeaveRequest.findById;
  const originalNotificationCreate = Notification.create;

  const mockLeaveId = new mongoose.Types.ObjectId();
  const mockCustomerId = new mongoose.Types.ObjectId();
  const mockVendorId = new mongoose.Types.ObjectId();

  const mockLeaveDoc = {
    _id: mockLeaveId,
    requestedBy: "Customer",
    status: "Pending",
    leaveDate: new Date(),
    customerId: mockCustomerId,
    vendorId: mockVendorId,
    mealType: "lunch",
    save: async function () {
      this.status = "Rejected";
      return this;
    },
  };

  LeaveRequest.findById = async () => mockLeaveDoc;

  let notificationDoc = null;
  Notification.create = async (doc) => {
    notificationDoc = doc;
    return doc;
  };

  try {
    const req = {
      params: { id: mockLeaveId.toString() },
      user: {
        userId: new mongoose.Types.ObjectId().toString(),
        role: "vendor",
        ownerId: mockVendorId.toString(),
      },
    };

    const res = {
      status: function () { return this; },
      json: function () { return this; },
    };

    await rejectLeave(req, res);

    assert.equal(mockLeaveDoc.status, "Rejected");
    assert.ok(notificationDoc);
    assert.equal(notificationDoc.customerId.toString(), mockCustomerId.toString());
    assert.equal(notificationDoc.type, "leave_rejected");
  } finally {
    LeaveRequest.findById = originalLeaveRequestFindById;
    Notification.create = originalNotificationCreate;
  }
});

