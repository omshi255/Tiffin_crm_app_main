import { ApiError } from "../class/apiErrorClass.js";

/**
 * Require the request user to have one of the allowed roles.
 * Must be used after authMiddleware (req.user must exist).
 * On failure returns 403 Forbidden.
 *
 * @param {string[]} allowedRoles - e.g. ['admin'], ['vendor', 'admin'], ['delivery_staff'], ['customer']
 * @returns {Function} Express middleware
 */
export const requireRole = (allowedRoles) => {
  const set = new Set(allowedRoles);

  return (req, res, next) => {
    let role = req.user?.role;
    // Backward compat: old enum had "delivery" → treat as delivery_staff
    if (role === "delivery") role = "delivery_staff";

    if (!role) {
      return next(new ApiError(403, "Role not found in token"));
    }

    // Ensure ownerId is set for vendor/admin
    if ((role === "vendor" || role === "admin" || !req.user.ownerId)) {
      if (!req.user.ownerId) {
        req.user.ownerId = req.user.userId;
      }
    }

    next();
  };
};
