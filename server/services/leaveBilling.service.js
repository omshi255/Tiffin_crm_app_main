import DailyOrder from "../models/DailyOrder.model.js";
import Subscription from "../models/Subscription.model.js";
import Customer from "../models/Customer.model.js";
import Transaction from "../models/Transaction.model.js";
import MealPlan from "../models/Plan.model.js";
import { parseUTC, splitPlanDailyPriceAcrossMealSlots } from "./dailyOrder.service.js";

const MEAL_ORDER = ["breakfast", "lunch", "dinner"];

export function expandLeaveMeals(mealType) {
  if (mealType === "all" || mealType === "both") return [...MEAL_ORDER];
  if (mealType === "early_morning") return ["breakfast"];
  if (MEAL_ORDER.includes(mealType)) return [mealType];
  return mealType ? [mealType] : [];
}

export function mealsOverlap(a, b) {
  const left = new Set(expandLeaveMeals(a));
  return expandLeaveMeals(b).some((meal) => left.has(meal));
}

export function sameUtcDay(a, b) {
  const left = parseUTC(a).getTime();
  const right = parseUTC(b).getTime();
  return left === right;
}

export function orderCoveredByLeave(order, leave) {
  if (!leave || leave.status !== "Approved") return false;
  if (!sameUtcDay(order.orderDate, leave.leaveDate)) return false;
  return mealsOverlap(order.mealType, leave.mealType);
}

export function isOrderWaived(order, approvedLeaves) {
  if (!order) return false;
  if (order.status === "cancelled") return false;
  const reason = String(order.cancellationReason || "");
  if (order.status === "skipped" && /leave|holiday/i.test(reason)) return true;
  return (approvedLeaves || []).some((leave) => orderCoveredByLeave(order, leave));
}

function round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

function linePrice(order) {
  const listed = Number(order.listPrice);
  if (listed > 0) return listed;
  return Number(order.amount) || 0;
}

/**
 * Build a monthly meal bill. Approved leave meals are listed at ₹0 and
 * excluded from the amount due.
 */
export function summarizeMonthlyBill({ orders = [], leaves = [] }) {
  const approved = leaves.filter((leave) => leave.status === "Approved");
  const used = new Set();
  const lines = [];
  let charged = 0;
  let excluded = 0;

  const sorted = [...orders].sort(
    (a, b) => new Date(a.orderDate) - new Date(b.orderDate)
  );

  for (const order of sorted) {
    if (order.status === "cancelled" || order.status === "failed") continue;
    const leave = approved.find((item) => orderCoveredByLeave(order, item));
    const waived = isOrderWaived(order, approved);
    if (waived) {
      const credit = linePrice(order);
      excluded += credit;
      if (leave?._id) used.add(String(leave._id));
      lines.push({
        kind: "leave",
        date: order.orderDate,
        mealType: order.mealType,
        description: `Leave — ${order.mealType || "meal"} not charged`,
        amount: 0,
        excluded: round2(credit),
        status: leave?.status || "Approved",
      });
      continue;
    }
    if (order.status === "skipped") continue;
    const amount = round2(order.amount || 0);
    charged += amount;
    lines.push({
      kind: "meal",
      date: order.orderDate,
      mealType: order.mealType,
      description: `Meal — ${order.mealType || "tiffin"}`,
      amount,
      excluded: 0,
      status: order.status,
    });
  }

  for (const leave of approved) {
    if (leave._id && used.has(String(leave._id))) continue;
    const meals = expandLeaveMeals(leave.mealType);
    const stored = Number(leave.waivedAmount) || 0;
    const each = meals.length ? stored / meals.length : stored;
    meals.forEach((meal) => {
      const credit = round2(each);
      excluded += credit;
      lines.push({
        kind: "leave",
        date: leave.leaveDate,
        mealType: meal,
        description: `Approved leave — ${meal} not charged`,
        amount: 0,
        excluded: credit,
        status: "Approved",
      });
    });
  }

  const approvedCount = approved.length;
  return {
    chargedAmount: round2(charged),
    leaveCredit: round2(excluded),
    grossAmount: round2(charged + excluded),
    netAmount: round2(charged),
    approvedLeaveCount: approvedCount,
    lines,
  };
}

async function refundChargedOrder(order) {
  const amount = Number(order.amount) || 0;
  if (!order.isCharged || amount <= 0) return 0;

  const walletPart = Number(order.walletCharged) || 0;
  let subscriptionPart =
    order.subscriptionCharged == null
      ? null
      : Number(order.subscriptionCharged) || 0;

  if (subscriptionPart == null) {
    subscriptionPart = order.subscriptionId ? Math.max(0, amount - walletPart) : 0;
  }

  if (order.subscriptionId && subscriptionPart > 0) {
    await Subscription.updateOne(
      { _id: order.subscriptionId },
      { $inc: { remainingBalance: subscriptionPart } }
    );
  }

  const walletRefund =
    walletPart > 0
      ? walletPart
      : !order.subscriptionId
        ? amount
        : 0;

  if (walletRefund > 0 && order.customerId) {
    await Customer.updateOne(
      { _id: order.customerId },
      { $inc: { walletBalance: walletRefund, balance: walletRefund } }
    );
  }

  await Transaction.create({
    ownerId: order.ownerId,
    customerId: order.customerId,
    date: new Date(),
    description: `Leave approved — ${order.mealType || "meal"} not charged`,
    amount,
    type: "credit",
    paymentMode: walletRefund > 0 ? "wallet" : "subscription",
    source: "leave_waiver",
    financeType: "refund",
  });

  return amount;
}

/**
 * Skip matching meals and reverse any charge already taken.
 * Returns the rupee amount removed from the customer's bill.
 */
export async function waiveOrdersForApprovedLeave(leaveRequest) {
  const day = parseUTC(leaveRequest.leaveDate);
  const next = new Date(day);
  next.setUTCDate(next.getUTCDate() + 1);

  const orders = await DailyOrder.find({
    subscriptionId: leaveRequest.subscriptionId,
    orderDate: { $gte: day, $lt: next },
    status: { $nin: ["cancelled", "failed"] },
  });

  let waived = 0;
  for (const order of orders) {
    if (!mealsOverlap(order.mealType, leaveRequest.mealType)) continue;

    const price = linePrice(order);
    if (order.status === "skipped" && /leave|holiday/i.test(order.cancellationReason || "")) {
      waived += price;
      continue;
    }

    if (order.isCharged && Number(order.amount) > 0) {
      waived += await refundChargedOrder(order);
    } else {
      waived += price;
    }

    if (!order.listPrice) order.listPrice = price;
    order.amount = 0;
    order.status = "skipped";
    order.cancellationReason =
      leaveRequest.requestedBy === "Vendor" ? "Vendor Holiday" : "Leave Approved";
    order.cancelledAt = order.cancelledAt || new Date();
    await order.save();
  }

  return round2(waived);
}

export async function estimateMealPrices(plan) {
  if (!plan) return {};
  const slots = plan.mealSlots?.length ? plan.mealSlots : null;
  if (!slots) {
    return { breakfast: 0, lunch: Number(plan.price) || 0, dinner: 0 };
  }
  const shares = splitPlanDailyPriceAcrossMealSlots(plan.price, slots.length);
  const prices = { breakfast: 0, lunch: 0, dinner: 0 };
  slots.forEach((slot, index) => {
    const meal = slot.slot === "early_morning" ? "breakfast" : slot.slot;
    if (prices[meal] != null) prices[meal] += shares[index] || 0;
  });
  return prices;
}

export async function loadPlanPricesForSubscription(subscriptionId) {
  const sub = await Subscription.findById(subscriptionId).select("planId").lean();
  if (!sub?.planId) return {};
  const plan = await MealPlan.findById(sub.planId).lean();
  return estimateMealPrices(plan);
}
