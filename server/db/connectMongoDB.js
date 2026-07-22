import mongoose from "mongoose";
import config from "../config/index.js";

const connectMongoDB = async () => {
  try {
    const conn = await mongoose.connect(config.MONGODB_URL, {
      autoIndex: config.NODE_ENV !== "production",
      maxPoolSize: 10,
      serverSelectionTimeoutMS: 5000,
    });

    console.log(`MongoDB connected => ${conn.connection.host}`);
  } catch (error) {
    console.error(`MongoDB connection error: ${error.message}`);

    // Fallback to local MongoDB if Cloud DNS/Internet fails
    const localUrl = "mongodb://127.0.0.1:27017/tiffin_crm";
    if (
      config.MONGODB_URL !== localUrl &&
      (error.message.includes("ENOTFOUND") ||
        error.message.includes("ECONNREFUSED") ||
        error.message.includes("selection timed out"))
    ) {
      console.warn("⚠️ Attempting fallback connection to local MongoDB server...");
      try {
        const localConn = await mongoose.connect(localUrl, {
          autoIndex: true,
          maxPoolSize: 10,
          serverSelectionTimeoutMS: 5000,
        });
        console.log(`✅ Connected to Local MongoDB => ${localConn.connection.host}`);
        return;
      } catch (localErr) {
        console.error(`Local MongoDB fallback error: ${localErr.message}`);
      }
    }

    process.exit(1);
  }
};

mongoose.connection.on("disconnected", () => {
  console.warn("MongoDB disconnected");
});

export default connectMongoDB;
