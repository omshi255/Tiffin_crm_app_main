import mongoose from "mongoose";
import Income from "../models/Income.model.js";
import Expense from "../models/Expense.model.js";
import DailyOrder from "../models/DailyOrder.model.js";
import Transaction from "../models/Transaction.model.js";
import Payment from "../models/Payment.model.js";
import Customer from "../models/Customer.model.js";

function asObjectId(id) {
  if (!id) return null;
  if (id instanceof mongoose.Types.ObjectId) return id;
  if (!mongoose.Types.ObjectId.isValid(id)) return null;
  return new mongoose.Types.ObjectId(id);
}

function money(n) {
  const v = Number(n || 0);
  return Number.isFinite(v) ? v : 0;
}

const IST_OFFSET_MS = 330 * 60 * 1000;
const MEAL_MIRROR_SOURCES = new Set([
  "order_delivered",
  "order_processing",
  "wallet_deduction",
]);
const DEPOSIT_SOURCES = new Set([
  "wallet_topup",
  "subscription_dues_payment",
  "deposit",
]);

function istParts(value) {
  const shifted = new Date(new Date(value).getTime() + IST_OFFSET_MS);
  return {
    key: `${pad2(shifted.getUTCDate())}/${pad2(shifted.getUTCMonth() + 1)}`,
    iso: `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`,
  };
}

function isDepositIncome(source) {
  return /deposit/i.test(String(source || ""));
}

/**
 * Ledger rows default financeType to "manual", so wallet top-ups and meal
 * charges were being added to revenue. Classify by source first.
 * Meal-charge mirrors return null because delivered orders already count them.
 */
function bucketTransaction(txn) {
  const source = String(txn.source || "").toLowerCase();
  const financeType = String(txn.financeType || "manual").toLowerCase();
  if (MEAL_MIRROR_SOURCES.has(source)) return null;
  if (DEPOSIT_SOURCES.has(source) || financeType === "deposit") return "deposit";
  if (source === "leave_waiver" || source === "refund" || financeType === "refund") {
    return "refund";
  }
  if (financeType === "expense" || source === "expense") return "expense";
  if (financeType === "processed" || source === "processed") return "processed";
  if (financeType === "income" || source.startsWith("extra_charge")) return "income";
  if (txn.type === "debit") return "expense";
  return "income";
}

function emptyDay() {
  return {
    processed: 0,
    processedCount: 0,
    income: 0,
    deposit: 0,
    expense: 0,
    refund: 0,
    manual: 0,
  };
}

/**
 * One pass used by the finance tab:
 * processed = delivered meals
 * deposit = customer payments (wallet, plan dues, captured payments)
 * income = other income and extra charges
 * expense = expense entries
 * refund = money returned (shown on its own; meals already removed from processed)
 * profit = processed + income - expenses
 */
export async function getFinanceBundle(ownerId, startDate, endDate) {
  const ownerOid = asObjectId(ownerId);
  if (!ownerOid) throw new Error("Invalid ownerId");

  const start = new Date(startDate);
  const end = new Date(endDate);
  const dateFilter = { date: { $gte: start, $lte: end } };
  const ownerFilter = { ownerId: ownerOid };

  const [incomes, expenses, transactions, deliveredOrders, payments, customers] =
    await Promise.all([
      Income.find({ ...ownerFilter, ...dateFilter }).lean(),
      Expense.find({ ...ownerFilter, ...dateFilter }).lean(),
      Transaction.find({ ...ownerFilter, ...dateFilter, status: "completed" }).lean(),
      DailyOrder.find({
        ...ownerFilter,
        orderDate: dateFilter.date,
        status: "delivered",
      })
        .select("amount orderDate customerId mealType")
        .lean(),
      Payment.find({
        ...ownerFilter,
        paymentDate: { $gte: start, $lte: end },
        status: { $in: ["captured", "refunded"] },
        type: { $ne: "order_deduction" },
      })
        .select("amount paymentDate status type customerId notes")
        .lean(),
      Customer.find({ ownerId: ownerOid, isDeleted: { $ne: true } })
        .select("name")
        .lean(),
    ]);

  const nameById = new Map(customers.map((c) => [String(c._id), c.name || "Customer"]));
  const who = (id) => nameById.get(String(id)) || "Customer";

  const dailyMap = {};
  const ensure = (key) => {
    if (!dailyMap[key]) dailyMap[key] = emptyDay();
    return dailyMap[key];
  };

  const ledger = [];

  for (const row of incomes) {
    const day = istParts(row.date);
    const bucket = ensure(day.key);
    const amount = money(row.amount);
    const deposit = isDepositIncome(row.source);
    if (deposit) bucket.deposit += amount;
    else bucket.income += amount;
    ledger.push({
      id: String(row._id),
      kind: deposit ? "deposit" : "income",
      date: day.iso,
      amount: +amount.toFixed(2),
      title: row.source || (deposit ? "Deposit" : "Income"),
      deletable: true,
      deleteAs: "income",
    });
  }

  for (const row of expenses) {
    const day = istParts(row.date);
    const amount = money(row.amount);
    ensure(day.key).expense += amount;
    ledger.push({
      id: String(row._id),
      kind: "expense",
      date: day.iso,
      amount: +amount.toFixed(2),
      title: row.title || "Expense",
      deletable: true,
      deleteAs: "expense",
    });
  }

  for (const row of transactions) {
    const bucketName = bucketTransaction(row);
    if (!bucketName) continue;
    const day = istParts(row.date);
    const amount = money(row.amount);
    const bucket = ensure(day.key);
    if (bucketName === "processed") {
      bucket.processed += amount;
      bucket.processedCount += 1;
    } else if (bucketName === "income") {
      bucket.income += amount;
    } else {
      bucket[bucketName] += amount;
    }
    const title =
      row.description ||
      (bucketName === "deposit"
        ? "Deposit"
        : bucketName === "refund"
          ? "Refund"
          : bucketName === "processed"
            ? "Processed"
            : bucketName === "expense"
              ? "Expense"
              : "Income");
    ledger.push({
      id: String(row._id),
      kind: bucketName === "processed" ? "processed" : bucketName,
      date: day.iso,
      amount: +amount.toFixed(2),
      title,
      deletable: false,
    });
  }

  for (const order of deliveredOrders) {
    const day = istParts(order.orderDate);
    const amount = money(order.amount);
    const bucket = ensure(day.key);
    bucket.processed += amount;
    bucket.processedCount += 1;
    const meal = order.mealType ? String(order.mealType) : "meal";
    ledger.push({
      id: String(order._id),
      kind: "processed",
      date: day.iso,
      amount: +amount.toFixed(2),
      title: `${who(order.customerId)} · ${meal}`,
      deletable: false,
    });
  }

  for (const payment of payments) {
    const day = istParts(payment.paymentDate);
    const amount = money(payment.amount);
    const refunded = payment.status === "refunded";
    const bucket = ensure(day.key);
    if (refunded) bucket.refund += amount;
    else bucket.deposit += amount;
    ledger.push({
      id: String(payment._id),
      kind: refunded ? "refund" : "deposit",
      date: day.iso,
      amount: +amount.toFixed(2),
      title: payment.notes || (refunded ? `${who(payment.customerId)} · Refund` : `${who(payment.customerId)} · Deposit`),
      deletable: false,
    });
  }

  const year = start.getUTCFullYear();
  const month = start.getUTCMonth() + 1;
  const dim = daysInMonth(year, month);
  for (let d = 1; d <= dim; d += 1) {
    ensure(`${pad2(d)}/${pad2(month)}`);
  }

  const totals = emptyDay();
  for (const values of Object.values(dailyMap)) {
    totals.processed += values.processed;
    totals.processedCount += values.processedCount;
    totals.income += values.income;
    totals.deposit += values.deposit;
    totals.expense += values.expense;
    totals.refund += values.refund;
    totals.manual += values.manual;
  }

  const profit = totals.processed + totals.income + totals.manual - totals.expense;
  const summary = {
    revenue: +money(totals.processed).toFixed(2),
    expenses: +money(totals.expense).toFixed(2),
    incomes: +money(totals.income).toFixed(2),
    deposit: +money(totals.deposit).toFixed(2),
    processed: +money(totals.processed).toFixed(2),
    refund: +money(totals.refund).toFixed(2),
    manual: +money(totals.manual).toFixed(2),
    profit: +money(profit).toFixed(2),
  };

  const daily = Object.entries(dailyMap)
    .map(([date, values]) => ({
      date,
      processed: +money(values.processed).toFixed(2),
      processedCount: values.processedCount || 0,
      income: +money(values.income).toFixed(2),
      deposit: +money(values.deposit).toFixed(2),
      expense: +money(values.expense).toFixed(2),
      refund: +money(values.refund).toFixed(2),
      manual: +money(values.manual).toFixed(2),
    }))
    .sort((a, b) => {
      const [da, ma] = a.date.split("/").map(Number);
      const [db, mb] = b.date.split("/").map(Number);
      return mb !== ma ? mb - ma : db - da;
    });

  ledger.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));

  return { summary, daily, transactions: ledger };
}

export async function getFinanceSummary(ownerId, startDate, endDate) {
  const bundle = await getFinanceBundle(ownerId, startDate, endDate);
  return bundle.summary;
}

function daysInMonth(year, month1to12) {
  return new Date(year, month1to12, 0).getDate();
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

export async function getDailyBreakdown(ownerId, startDate, endDate) {
  const bundle = await getFinanceBundle(ownerId, startDate, endDate);
  return bundle.daily;
}

