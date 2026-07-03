import mongoose from "mongoose";
import dotenv from "dotenv";

dotenv.config({ path: "./config/.env" });

import config from "./config/index.js";
import Customer from "./models/Customer.model.js";
import DeliveryStaff from "./models/DeliveryStaff.model.js";
import User from "./models/User.model.js";

async function run() {
  await mongoose.connect(config.MONGODB_URL);
  console.log("Connected to MongoDB");

  console.log("\n--- USERS ---");
  const users = await User.find({}).lean();
  for (const u of users) {
    console.log(`ID: ${u._id}, Phone: ${u.phone}, Role: ${u.role}, Name: ${u.name || u.ownerName || ""}`);
  }

  console.log("\n--- CUSTOMERS ---");
  const customers = await Customer.find({}).lean();
  for (const c of customers) {
    console.log(`ID: ${c._id}, Phone: ${c.phone}, Name: ${c.name}, OwnerId: ${c.ownerId}, Status: ${c.status}`);
  }

  console.log("\n--- DELIVERY STAFF ---");
  const staff = await DeliveryStaff.find({}).lean();
  for (const s of staff) {
    console.log(`ID: ${s._id}, Phone: ${s.phone}, Name: ${s.name}, OwnerId: ${s.ownerId}, IsActive: ${s.isActive}`);
  }

  await mongoose.disconnect();
}

run().catch(console.error);
