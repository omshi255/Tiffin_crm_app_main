import mongoose from "mongoose";

let supportsTransactions;

/**
 * Standalone MongoDB (local dev) rejects multi-document transactions.
 * Skip them there so wallet and ledger writes still succeed. Replica sets
 * and Atlas keep real transactions.
 */
export async function installStandaloneTransactionFallback() {
  if (mongoose.startSession.__txnFallback) return;

  try {
    const hello = await mongoose.connection.db.admin().command({ hello: 1 });
    supportsTransactions = Boolean(hello.setName) || hello.msg === "isdbgrid";
  } catch {
    supportsTransactions = false;
  }

  if (supportsTransactions) {
    console.log("MongoDB transactions enabled");
    mongoose.startSession.__txnFallback = true;
    return;
  }

  console.warn(
    "MongoDB transactions unavailable on this server; writes will run without a transaction"
  );

  const originalStartSession = mongoose.startSession.bind(mongoose);
  mongoose.startSession = async function startSessionWithoutTransaction(...args) {
    const session = await originalStartSession(...args);
    const commit = session.commitTransaction.bind(session);
    const abort = session.abortTransaction.bind(session);

    session.startTransaction = function skipStartTransaction() {
      session.__txnSkipped = true;
    };
    session.commitTransaction = async function skipCommit(...commitArgs) {
      if (session.__txnSkipped) return;
      return commit(...commitArgs);
    };
    session.abortTransaction = async function skipAbort(...abortArgs) {
      if (session.__txnSkipped) return;
      try {
        return await abort(...abortArgs);
      } catch (err) {
        if (String(err?.message || "").includes("No transaction started")) return;
        throw err;
      }
    };
    session.withTransaction = async function skipWithTransaction(fn) {
      return fn();
    };
    return session;
  };
  mongoose.startSession.__txnFallback = true;
}
