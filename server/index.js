import { createServer } from "http";
import { Server } from "socket.io";
import mongoose from "mongoose";
import { app } from "./server.js";
import dotenv from "dotenv";
import connectMongoDB from "./db/connectMongoDB.js";
import config from "./config/index.js";
import { startDeliveryCron } from "./jobs/deliveryCron.js";
import { startSubscriptionExpiryCron } from "./jobs/subscriptionExpiryCron.js";
import { initDeliverySocket } from "./socket/delivery.socket.js";

dotenv.config({ path: "./config/.env" });

const PORT = config.PORT || 5000;

const httpServer = createServer(app);

const io = new Server(httpServer, {
  cors: {
    origin:
      config.NODE_ENV === "production" ? process.env.CORS_ORIGIN || "*" : "*",
  },
});

app.set("io", io);

// ─── process-level safety nets ────────────────────────────────────────────────

process.on("unhandledRejection", (reason) => {
  console.error("Unhandled Promise Rejection:", reason);
  // Log but don't exit — let the request time out cleanly.
});

process.on("uncaughtException", (err) => {
  console.error("Uncaught Exception:", err);
  process.exit(1); // Force restart so the process doesn't continue in a broken state.
});

const gracefulShutdown = async (signal) => {
  console.log(`${signal} received — shutting down gracefully`);
  httpServer.close(async () => {
    await mongoose.connection.close();
    console.log("MongoDB connection closed");
    process.exit(0);
  });
  // Force exit if graceful shutdown takes too long
  setTimeout(() => process.exit(1), 10_000);
};

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));

// ─── startup ──────────────────────────────────────────────────────────────────
// Listen first. Waiting for MongoDB before listen makes Render hold the login
// request with no response, and the app times out after 30 seconds.

app.on("error", (error) => {
  console.error(`App error: ${error}`);
});

httpServer.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on port ${PORT}`);
});

let backgroundJobsStarted = false;

async function connectAndStartJobs() {
  for (;;) {
    try {
      await connectMongoDB();
      if (!backgroundJobsStarted) {
        startDeliveryCron();
        startSubscriptionExpiryCron();
        initDeliverySocket(io);
        backgroundJobsStarted = true;
      }
      console.log("Database ready");
      return;
    } catch (error) {
      const reason = error?.message || error;
      console.error(`DB connection failed: ${reason}. Retrying in 10s`);
      await new Promise((resolve) => setTimeout(resolve, 10_000));
    }
  }
}

connectAndStartJobs();
