import test from "node:test";
import assert from "node:assert/strict";
import { summarizeMonthlyBill } from "../services/leaveBilling.service.js";
import { isCutoffExceeded } from "../utils/leaveValidation.js";

test("monthly bill excludes approved leave meals", () => {
  const day = new Date("2026-11-10T00:00:00Z");
  const summary = summarizeMonthlyBill({
    orders: [
      {
        orderDate: day,
        mealType: "lunch",
        status: "delivered",
        amount: 80,
        listPrice: 80,
      },
      {
        orderDate: day,
        mealType: "dinner",
        status: "skipped",
        amount: 0,
        listPrice: 90,
        cancellationReason: "Leave Approved",
      },
    ],
    leaves: [
      {
        _id: "leave-1",
        status: "Approved",
        leaveDate: day,
        mealType: "dinner",
        waivedAmount: 90,
      },
    ],
  });

  assert.equal(summary.chargedAmount, 80);
  assert.equal(summary.leaveCredit, 90);
  assert.equal(summary.netAmount, 80);
  assert.equal(summary.lines.filter((line) => line.kind === "leave").length, 1);
});

test("breakfast is still open at exactly 8:00 AM IST", () => {
  const originalDate = global.Date;
  const mockNow = new originalDate("2026-07-21T02:30:00Z");
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
    assert.equal(isCutoffExceeded("2026-07-21", "breakfast", 330), false);
    assert.equal(isCutoffExceeded("2026-07-21", "breakfast", 331), true);
  } finally {
    global.Date = originalDate;
  }
});
