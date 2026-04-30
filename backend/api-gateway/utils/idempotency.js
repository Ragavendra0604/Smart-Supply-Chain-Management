import { db } from '../config/firebase.js';

/**
 * Idempotent Event Processor
 * Ensures each event is processed exactly once by checking a processed_events collection.
 */
export const processIdempotentEvent = async (eventId, processingLogic) => {
  const eventRef = db().collection('processed_events').doc(eventId);

  try {
    return await db().runTransaction(async (transaction) => {
      const doc = await transaction.get(eventRef);

      if (doc.exists) {
        console.log(`[IDEMPOTENCY] Event ${eventId} already processed. Skipping.`);
        return { success: true, processed: false };
      }

      // Mark as processing
      transaction.set(eventRef, {
        processed_at: new Date(),
        status: 'PROCESSING'
      });

      // Execute actual business logic
      const result = await processingLogic();

      // Update to COMPLETED
      transaction.update(eventRef, {
        status: 'COMPLETED',
        result: result || null
      });

      return { success: true, processed: true, result };
    });
  } catch (error) {
    console.error(`[IDEMPOTENCY ERROR] Event ${eventId} failed:`, error.message);
    // In a real system, this would move to a Dead Letter Queue (DLQ)
    await eventRef.set({ status: 'FAILED', error: error.message }, { merge: true });
    throw error;
  }
};
