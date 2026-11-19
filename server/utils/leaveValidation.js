import config from "../config/index.js";

const DEFAULT_OFFSET_MINUTES = 330;

function cutoffMinutes() {
  const parse = (timeStr) => {
    const [h, m] = String(timeStr || "00:00").split(":").map(Number);
    return (h || 0) * 60 + (m || 0);
  };
  return {
    breakfast: parse(config.LEAVE_CUTOFFS.breakfast),
    lunch: parse(config.LEAVE_CUTOFFS.lunch),
    dinner: parse(config.LEAVE_CUTOFFS.dinner),
  };
}

function localParts(date, offsetMinutes) {
  const shifted = new Date(date.getTime() + offsetMinutes * 60 * 1000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    minutes: shifted.getUTCHours() * 60 + shifted.getUTCMinutes(),
  };
}

/** Calendar day the customer picked. Date-only strings stay on that day. */
export function calendarFromLeaveInput(value) {
  if (typeof value === "string") {
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (match) {
      return { year: Number(match[1]), month: Number(match[2]), day: Number(match[3]) };
    }
  }
  const date = value instanceof Date ? value : new Date(value);
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
}

function calendarKey(parts) {
  return parts.year * 10000 + parts.month * 100 + parts.day;
}

function mealsToCheck(mealType) {
  if (mealType === "both" || mealType === "all") return ["breakfast", "lunch", "dinner"];
  if (mealType === "breakfast" || mealType === "lunch" || mealType === "dinner") {
    return [mealType];
  }
  return [];
}

export function formatCutoff(meal) {
  const raw = config.LEAVE_CUTOFFS[meal] || "00:00";
  const [h, m] = raw.split(":").map(Number);
  const suffix = h >= 12 ? "PM" : "AM";
  const hour = h % 12 === 0 ? 12 : h % 12;
  const minute = String(m || 0).padStart(2, "0");
  return `${hour}:${minute} ${suffix}`;
}

/**
 * True when the customer can no longer request this meal.
 * A request at the exact cutoff is still accepted; only times after it are closed.
 * `offsetMinutes` is the customer's timezone offset from UTC (IST = 330).
 */
export const isCutoffExceeded = (
  leaveDate,
  mealType,
  offsetMinutes = DEFAULT_OFFSET_MINUTES
) => {
  const offset = Number.isFinite(Number(offsetMinutes))
    ? Number(offsetMinutes)
    : DEFAULT_OFFSET_MINUTES;
  const now = localParts(new Date(), offset);
  const leave = calendarFromLeaveInput(leaveDate);
  const leaveKey = calendarKey(leave);
  const nowKey = calendarKey(now);

  if (leaveKey < nowKey) return true;
  if (leaveKey > nowKey) return false;

  const cutoffs = cutoffMinutes();
  return mealsToCheck(mealType).some((meal) => {
    const limit = cutoffs[meal];
    if (limit == null) return false;
    return now.minutes > limit;
  });
};

export function cutoffRejectionMessage(leaveDate, mealType, offsetMinutes) {
  const offset = Number.isFinite(Number(offsetMinutes))
    ? Number(offsetMinutes)
    : DEFAULT_OFFSET_MINUTES;
  const now = localParts(new Date(), offset);
  const leave = calendarFromLeaveInput(leaveDate);
  if (calendarKey(leave) < calendarKey(now)) {
    return "Cannot request leave for a past date";
  }
  if (calendarKey(leave) > calendarKey(now)) return null;
  const cutoffs = cutoffMinutes();
  for (const meal of mealsToCheck(mealType)) {
    if (now.minutes > cutoffs[meal]) {
      const label = meal.charAt(0).toUpperCase() + meal.slice(1);
      return `${label} leave cannot be requested after ${formatCutoff(meal)}.`;
    }
  }
  return null;
}
