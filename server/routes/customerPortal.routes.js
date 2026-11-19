import { Router } from "express";
import {
  getMyProfile,
  getMyBalance,
  updateMyProfile,
  getMyActivePlan,
  getMyOrders,
  getMyNotifications,
  markNotificationRead,
  deleteNotification,
  clearReadNotifications,
  markAllNotificationsRead,
} from "../controllers/customerPortal.controller.js";
import {
  getMyMonthlyBill,
  downloadMyMonthlyBill,
} from "../controllers/customerBill.controller.js";
import { authMiddleware } from "../middleware/auth.middleware.js";
import { requireRole } from "../middleware/rbac.middleware.js";

const router = Router();

router.use(authMiddleware);
router.use(requireRole(["customer", "vendor", "admin"]));

router.get("/me", getMyProfile);
router.get("/me/balance", getMyBalance);
router.put("/me", updateMyProfile);
router.get("/me/plan", getMyActivePlan);
router.get("/me/orders", getMyOrders);
router.get("/me/notifications", getMyNotifications);
router.patch("/me/notifications/:id/read", markNotificationRead);
router.delete("/me/notifications/:id", deleteNotification);
router.delete("/me/notifications/clear-read", clearReadNotifications);
router.patch("/me/notifications/read-all", markAllNotificationsRead);
router.get("/me/monthly-bill", getMyMonthlyBill);
router.get("/me/monthly-bill/pdf", downloadMyMonthlyBill);

export default router;
