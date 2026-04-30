import { db } from '../config/firebase.js';

/**
 * Production Idempotency check using Firestore transactions.
 * Client must send a unique UUIDv4 per action.
 */
export const processIdempotentRequest = async (idempotencyKey, processorFn) => {
  if (!idempotencyKey) {
    throw new Error('Idempotency key is required for mutation operations.');
  }

  const ref = db().collection('idempotency_keys').doc(idempotencyKey);

  return await db().runTransaction(async (t) => {
    const doc = await t.get(ref);
    if (doc.exists) {
      console.log(`[IDEMPOTENCY] Key ${idempotencyKey} already processed. Returning cached result.`);
      return doc.data().result; // Return previous successful response
    }

    // Process the actual business logic
    const result = await processorFn();

    // Store the result with a TTL (requires Firestore TTL policy on 'expiresAt')
    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + 24); // Keep for 24h

    t.set(ref, {
      processedAt: new Date(),
      result,
      expiresAt
    });

    return result;
  });
};
