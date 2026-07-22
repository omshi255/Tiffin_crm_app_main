import config from "../config/index.js";

/**
 * Checks if the cutoff time for a given leave request has been exceeded.
 *
 * @param {Date|string} leaveDate - The date of the leave
 * @param {string} mealType - The meal type (breakfast, lunch, dinner, both, all)
 * @param {string} timezone - Timezone to evaluate date & time in (defaults to Asia/Kolkata)
 * @returns {boolean} True if the cutoff is exceeded, false otherwise
 */
export const isCutoffExceeded = (leaveDate, mealType, timezone = "Asia/Kolkata") => {
  const now = new Date();

  // Convert now and leaveDate to local calendar date strings in the target timezone
  const getLocalDateString = (d) => {
    return d.toLocaleDateString("en-US", { timeZone: timezone });
  };

  const leaveLocalDateStr = getLocalDateString(new Date(leaveDate));
  const nowLocalDateStr = getLocalDateString(now);

  const leaveDateObj = new Date(leaveLocalDateStr);
  const nowDateObj = new Date(nowLocalDateStr);

  // If the leave date is in the past, preparation has already happened
  if (leaveDateObj < nowDateObj) {
    return true;
  }

  // If the leave date is in the future, preparation hasn't started
  if (leaveDateObj > nowDateObj) {
    return false;
  }

  // If the leave date is today, check the meal cutoffs
  const localTimeStr = now.toLocaleTimeString("en-US", {
    timeZone: timezone,
    hour12: false,
    hour: "2-digit",
    minute: "2-digit",
  });

  const [currentHour, currentMinute] = localTimeStr.split(":").map(Number);
  const currentMinutesSinceMidnight = currentHour * 60 + currentMinute;

  const parseConfigTimeToMinutes = (timeStr) => {
    const [h, m] = timeStr.split(":").map(Number);
    return h * 60 + m;
  };

  const cutoffs = {
    breakfast: parseConfigTimeToMinutes(config.LEAVE_CUTOFFS.breakfast),
    lunch: parseConfigTimeToMinutes(config.LEAVE_CUTOFFS.lunch),
    dinner: parseConfigTimeToMinutes(config.LEAVE_CUTOFFS.dinner),
  };

  const checkMealCutoff = (meal) => {
    if (meal === "breakfast" && currentMinutesSinceMidnight >= cutoffs.breakfast) return true;
    if (meal === "lunch" && currentMinutesSinceMidnight >= cutoffs.lunch) return true;
    if (meal === "dinner" && currentMinutesSinceMidnight >= cutoffs.dinner) return true;
    return false;
  };

  // Map the request's mealType to the individual meals to check
  let mealsToCheck = [];
  if (mealType === "breakfast") {
    mealsToCheck = ["breakfast"];
  } else if (mealType === "lunch") {
    mealsToCheck = ["lunch"];
  } else if (mealType === "dinner") {
    mealsToCheck = ["dinner"];
  } else if (mealType === "both" || mealType === "all") {
    mealsToCheck = ["breakfast", "lunch", "dinner"];
  }

  // If any of the requested meals has exceeded its cutoff, the cutoff is exceeded
  for (const meal of mealsToCheck) {
    if (checkMealCutoff(meal)) {
      return true;
    }
  }

  return false;
};
