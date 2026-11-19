import mongoose from "mongoose";

const leaveRequestSchema = new mongoose.Schema(
  {
    requestedBy: {
      type: String,
      enum: ["Customer", "Vendor"],
      required: true,
    },
    customerId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Customer",
      required: true,
    },
    vendorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      required: true,
    },
    subscriptionId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Subscription",
    },
    mealType: {
      type: String,
      enum: ["breakfast", "lunch", "dinner", "both", "all"],
      default: "all",
    },
    leaveDate: {
      type: Date,
      required: true,
    },
    reason: {
      type: String,
      trim: true,
      default: "",
    },
    notes: {
      type: String,
      trim: true,
      default: "",
    },
    status: {
      type: String,
      enum: ["Pending", "Approved", "Rejected"],
      default: "Pending",
    },
    approvedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
    },
    approvedAt: {
      type: Date,
    },
    rejectedAt: {
      type: Date,
    },
    /** Rupees removed from the bill when this leave was approved. */
    waivedAmount: {
      type: Number,
      default: 0,
      min: 0,
    },
    /** Customer timezone offset from UTC, in minutes, at the time of the request. */
    timezoneOffsetMinutes: {
      type: Number,
      default: 330,
    },
  },
  {
    timestamps: true,
  }
);

leaveRequestSchema.index({ customerId: 1, leaveDate: 1 });
leaveRequestSchema.index({ vendorId: 1, leaveDate: 1 });
leaveRequestSchema.index({ subscriptionId: 1 });
leaveRequestSchema.index({ status: 1 });

const LeaveRequest = mongoose.model("LeaveRequest", leaveRequestSchema);

export default LeaveRequest;
