import { Router } from "express";
import {
  requestLeave,
  requestVendorLeave,
  getCustomerLeaves,
  getVendorLeaves,
  approveLeave,
  rejectLeave,
  getLeaveHistory,
} from "../controllers/leave.controller.js";
import { authMiddleware } from "../middleware/auth.middleware.js";
import { requireRole } from "../middleware/rbac.middleware.js";

const router = Router();

// Apply authentication middleware globally to all leave routes
router.use(authMiddleware);

// Leave request endpoints (accessible by customer, vendor, and admin)
router.post("/request", requireRole(["customer", "vendor", "admin"]), requestLeave);
router.get("/customer", requireRole(["customer", "vendor", "admin"]), getCustomerLeaves);

// Vendor leave request endpoints
router.post("/vendor/request", requireRole(["vendor", "admin", "customer"]), requestVendorLeave);
router.get("/vendor", requireRole(["vendor", "admin", "customer"]), getVendorLeaves);

// Common approval/rejection endpoints
router.put("/:id/approve", requireRole(["vendor", "admin", "customer"]), approveLeave);
router.put("/:id/reject", requireRole(["vendor", "admin", "customer"]), rejectLeave);

// Common history endpoint
router.get("/history", requireRole(["vendor", "admin", "customer"]), getLeaveHistory);

export default router;
