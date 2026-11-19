import DeliveryStaff from "../models/DeliveryStaff.model.js";
import Customer from "../models/Customer.model.js";
import MealPlan from "../models/Plan.model.js";
import Subscription from "../models/Subscription.model.js";

/**
 * Check if this user has vendor business data (customers, plans, or subscriptions).
 * Used to protect real vendors from abuse: a malicious vendor could add another
 * vendor's phone as customer to hijack their role. We only override vendor→customer
 * when the user has NO business data (likely "accidental vendor").
 *
 * @param {string} userId - User._id
 * @returns {Promise<boolean>} true if they have any customers, plans, or subscriptions
 */
export const hasVendorBusinessData = async (userId) => {
  const [customers, plans, subs] = await Promise.all([
    Customer.countDocuments({ ownerId: userId, isDeleted: { $ne: true } }),
    MealPlan.countDocuments({ ownerId: userId }),
    Subscription.countDocuments({ ownerId: userId }),
  ]);
  return customers > 0 || plans > 0 || subs > 0;
};

/**
 * Resolve role and ownerId for a phone number from existing data.
 * Used at login to know if the person is vendor, customer, or delivery_staff
 * without asking them.
 *
 * Logic:
 * - If phone exists in DeliveryStaff (any vendor added them) → delivery_staff + that vendor's ownerId
 * - Else if phone exists in Customer (any vendor added them) → customer + that vendor's ownerId
 * - Else → vendor (self-registering business owner), ownerId will be set to userId in auth
 *
 * @param {string} phone - 10-digit Indian mobile
 * @returns {Promise<{ role: 'vendor'|'customer'|'delivery_staff', ownerId?: string }>}
 */
export const resolveRoleForPhone = async (phone) => {
  const normalized = String(phone).replace(/\D/g, "").slice(-10);
  if (normalized.length < 10) {
    return { role: "vendor", ownerId: null };
  }

  // Create a regex to match the phone number ending with the 10-digit normalized number
  // and allowing optional non-digits (like spaces or dashes) in between.
  const regexPattern = normalized.split("").join("\\D*") + "$";
  const phoneRegex = new RegExp(regexPattern);

  const [staff, customer] = await Promise.all([
    DeliveryStaff.findOne({
      phone: phoneRegex,
      isActive: true,
    })
      .select("ownerId userId")
      .lean(),
    Customer.find({
      phone: phoneRegex,
      isDeleted: { $ne: true },
    })
      .select("ownerId _id status")
      .sort({ updatedAt: -1 })
      .lean(),
  ]);

  if (staff) {
    return {
      role: "delivery_staff",
      ownerId: staff.ownerId.toString(),
      staffId: staff._id.toString(),
    };
  }
  const savedCustomer = Array.isArray(customer)
    ? customer.find((row) => row.status === "active") || customer[0]
    : null;
  if (savedCustomer) {
    return {
      role: "customer",
      ownerId: savedCustomer.ownerId.toString(),
      customerId: savedCustomer._id.toString(),
    };
  }

  return { role: "vendor", ownerId: null };
};
