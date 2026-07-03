import mongoose from "mongoose";
import dotenv from "dotenv";

dotenv.config({ path: "./config/.env" });

import config from "./config/index.js";
import DeliveryStaff from "./models/DeliveryStaff.model.js";

async function run() {
  await mongoose.connect(config.MONGODB_URL);
  console.log("Connected to MongoDB");

  const activeStaff = await DeliveryStaff.find({ isActive: true }).select("phone name ownerId").lean();
  console.log("Active Delivery Staff:");
  for (const s of activeStaff) {
    console.log(`Phone: ${s.phone}, Name: ${s.name}, OwnerId: ${s.ownerId}`);
  }

  await mongoose.disconnect();
}

run().catch(console.error);
