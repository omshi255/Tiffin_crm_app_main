import mongoose from "mongoose";
import config from "../config/index.js";
import { installStandaloneTransactionFallback } from "../utils/mongoSession.js";

// Don't queue API calls while the database is still connecting. Those calls
// would sit until the client times out. Routes answer 503 instead.
mongoose.set("bufferCommands", false);

const connectOptions = {
  autoIndex: config.NODE_ENV !== "production",
  maxPoolSize: 10,
  serverSelectionTimeoutMS: 8000,
};

const connectMongoDB = async () => {
  try {
    const conn = await mongoose.connect(config.MONGODB_URL, connectOptions);

    console.log(`MongoDB connected => ${conn.connection.host}`);
    await installStandaloneTransactionFallback();
    return;
  } catch (error) {
    console.error(`MongoDB connection error: ${error.message}`);

    // Local fallback is for this computer only. On Render it adds another
    // failed wait before the process gives up, which is what makes login hang.
    const localUrl = "mongodb://127.0.0.1:27017/tiffin_crm";
    const canUseLocal =
      config.NODE_ENV !== "production" &&
      config.MONGODB_URL !== localUrl &&
      (error.message.includes("ENOTFOUND") ||
        error.message.includes("ECONNREFUSED") ||
        error.message.includes("querySrv") ||
        error.message.includes("selection timed out") ||
        error.message.includes("whitelist") ||
        error.message.includes("Could not connect"));

    if (canUseLocal) {
      console.warn("Attempting fallback connection to local MongoDB server...");
      try {
        const localConn = await mongoose.connect(localUrl, {
          ...connectOptions,
          autoIndex: true,
        });
        console.log(`Connected to Local MongoDB => ${localConn.connection.host}`);
        await installStandaloneTransactionFallback();
        return;
      } catch (localErr) {
        console.error(`Local MongoDB fallback error: ${localErr.message}`);
      }
    }

    throw error;
  }
};

mongoose.connection.on("disconnected", () => {
  console.warn("MongoDB disconnected");
});

export default connectMongoDB;
