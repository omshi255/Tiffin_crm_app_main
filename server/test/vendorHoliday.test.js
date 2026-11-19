import test from "node:test";
import assert from "node:assert/strict";
import mongoose from "mongoose";
import User from "../models/User.model.js";
import Customer from "../models/Customer.model.js";
import Subscription from "../models/Subscription.model.js";
import DailyOrder from "../models/DailyOrder.model.js";
import Notification from "../models/Notification.model.js";
import LeaveRequest from "../models/LeaveRequest.model.js";

const localUrl = "mongodb://127.0.0.1:27017/tiffin_crm";

test("vendor holiday notifies once, waives every meal, and leaves other vendors alone", async (t) => {
  try {
    await mongoose.connect(localUrl, { serverSelectionTimeoutMS: 4000 });
  } catch (err) {
    t.skip(`local database unavailable: ${err.message}`);
    return;
  }

  const planId = new mongoose.Types.ObjectId();
  const tomorrow = new Date();
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
  tomorrow.setUTCHours(0, 0, 0, 0);
  const dayAfter = new Date(tomorrow);
  dayAfter.setUTCDate(dayAfter.getUTCDate() + 1);
  const ymd = tomorrow.toISOString().slice(0, 10);

  const vendor = await User.create({
    phone: "9111100001",
    role: "vendor",
    businessName: "Holiday Kitchen",
    ownerName: "Holiday Owner",
  });
  const other = await User.create({
    phone: "9222200002",
    role: "vendor",
    businessName: "Other Kitchen",
    ownerName: "Other Owner",
  });
  const customer = await Customer.create({
    ownerId: vendor._id,
    name: "Holiday Customer",
    phone: "9333300003",
    address: "Lane 1",
  });
  const extraCustomer = await Customer.create({
    ownerId: vendor._id,
    name: "Extra Customer",
    phone: "9555500005",
    address: "Lane 3",
  });
  const otherCustomer = await Customer.create({
    ownerId: other._id,
    name: "Other Customer",
    phone: "9444400004",
    address: "Lane 2",
  });
  const sub = await Subscription.create({
    ownerId: vendor._id,
    customerId: customer._id,
    planId,
    startDate: tomorrow,
    endDate: dayAfter,
    totalAmount: 1000,
    status: "active",
  });
  const otherSub = await Subscription.create({
    ownerId: other._id,
    customerId: otherCustomer._id,
    planId,
    startDate: tomorrow,
    endDate: dayAfter,
    totalAmount: 1000,
    status: "active",
  });
  const ids = {
    users: [vendor._id, other._id],
    customers: [customer._id, extraCustomer._id, otherCustomer._id],
    subs: [sub._id, otherSub._id],
    owners: [vendor._id, other._id],
  };

  try {
    await DailyOrder.create([
      { ownerId: vendor._id, customerId: customer._id, subscriptionId: sub._id, planId, orderDate: tomorrow, planMealSlot: "breakfast", mealType: "breakfast", amount: 40, listPrice: 40, status: "pending" },
      { ownerId: vendor._id, customerId: customer._id, subscriptionId: sub._id, planId, orderDate: tomorrow, planMealSlot: "lunch", mealType: "lunch", amount: 54, listPrice: 54, status: "pending" },
      { ownerId: vendor._id, customerId: customer._id, subscriptionId: sub._id, planId, orderDate: tomorrow, planMealSlot: "dinner", mealType: "dinner", amount: 70, listPrice: 70, status: "pending" },
      { ownerId: vendor._id, customerId: customer._id, subscriptionId: sub._id, planId, orderDate: dayAfter, planMealSlot: "lunch", mealType: "lunch", amount: 54, listPrice: 54, status: "pending" },
      { ownerId: other._id, customerId: otherCustomer._id, subscriptionId: otherSub._id, planId, orderDate: tomorrow, planMealSlot: "lunch", mealType: "lunch", amount: 80, listPrice: 80, status: "pending" },
    ]);

    const login = await fetch("http://127.0.0.1:5800/api/v1/auth/send-otp", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phone: "9111100001", role: "vendor" }),
    });
    const token = (await login.json()).data.accessToken;
    const headers = {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    };
    const declareHoliday = (mealType) =>
      fetch("http://127.0.0.1:5800/api/v1/leave/vendor/request", {
        method: "POST",
        headers,
        body: JSON.stringify({ leaveDate: ymd, mealType, reason: "Kitchen closed" }),
      });

    const first = await declareHoliday("lunch");
    const firstBody = await first.json();
    const second = await declareHoliday("all");
    const secondBody = await second.json();

    const holidayOrders = await DailyOrder.find({ ownerId: vendor._id, orderDate: tomorrow }).lean();
    const nextDay = await DailyOrder.findOne({ ownerId: vendor._id, orderDate: dayAfter }).lean();
    const otherOrder = await DailyOrder.findOne({ ownerId: other._id, orderDate: tomorrow }).lean();
    const notes = await Notification.find({ customerId: customer._id, type: "vendor_holiday" }).lean();
    const extraNotes = await Notification.find({ customerId: extraCustomer._id, type: "vendor_holiday" }).lean();
    const otherNotes = await Notification.countDocuments({
      customerId: otherCustomer._id,
      type: "vendor_holiday",
    });
    const leaveRows = await LeaveRequest.countDocuments({
      vendorId: vendor._id,
      requestedBy: "Vendor",
    });

    assert.equal(first.status, 201);
    assert.match(firstBody.message, /customer\(s\) notified/);
    assert.equal(second.status, 200);
    assert.equal(secondBody.message, "Holiday is already declared for this date.");
    assert.equal(holidayOrders.length, 3);
    for (const order of holidayOrders) {
      assert.equal(order.status, "skipped");
      assert.equal(order.amount, 0);
      assert.equal(order.cancellationReason, "Vendor Holiday");
    }
    assert.equal(nextDay.status, "pending");
    assert.equal(nextDay.amount, 54);
    assert.equal(otherOrder.status, "pending");
    assert.equal(otherOrder.amount, 80);
    assert.equal(notes.length, 1);
    assert.equal(
      notes[0].message,
      "Your meal vendor has declared a holiday for today. No meals will be provided today."
    );
    assert.equal(extraNotes.length, 1);
    assert.equal(extraNotes[0].message, notes[0].message);
    assert.equal(otherNotes, 0);
    assert.equal(leaveRows, 2);
    const extraLeave = await LeaveRequest.findOne({
      customerId: extraCustomer._id,
      requestedBy: "Vendor",
      status: "Approved",
    }).lean();
    assert.ok(extraLeave, "unsubscribed customer should have an approved holiday leave");
  } finally {
    await DailyOrder.deleteMany({ ownerId: { $in: ids.owners } });
    await LeaveRequest.deleteMany({ vendorId: { $in: ids.owners } });
    await Notification.deleteMany({ ownerId: { $in: ids.owners } });
    await Subscription.deleteMany({ _id: { $in: ids.subs } });
    await Customer.deleteMany({ _id: { $in: ids.customers } });
    await User.deleteMany({ _id: { $in: ids.users } });
    await mongoose.disconnect();
  }
});
