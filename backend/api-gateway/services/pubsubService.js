import { PubSub } from '@google-cloud/pubsub';

const pubsub = new PubSub();
const TOPIC_NAME = 'shipment-telemetry';

/**
 * PRODUCTION PIPELINE: Distributed Event-Driven Architecture
 * Replaces local EventEmitter to handle 10,000+ concurrent vehicles.
 */
export const publishEvent = async (eventType, data) => {
  try {
    // If no real Pub/Sub credentials, fallback to local logging for demo
    if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      console.log(`[MOCK-PUBSUB] Event: ${eventType} | Data: ${data.shipment_id}`);
      return;
    }

    const topic = pubsub.topic(TOPIC_NAME);
    const messageBuffer = Buffer.from(JSON.stringify({
      eventType,
      ...data,
      timestamp: new Date().toISOString()
    }));

    const messageId = await topic.publishMessage({ data: messageBuffer });
    console.log(`[PUBSUB] Message ${messageId} published to ${TOPIC_NAME}`);
  } catch (err) {
    console.error(`[PUBSUB ERROR] Failed to publish ${eventType}:`, err.message);
    // In production, implement a local "Outbox Pattern" database retry if Pub/Sub is down
  }
};

/**
 * Feedback Loop Listener
 * Listens for analysis completion to log for BigQuery retraining.
 */
export const setupSubscribers = () => {
  const subscription = pubsub.subscription('ai-retraining-sub');

  subscription.on('message', message => {
    const data = JSON.parse(message.data.toString());
    console.log(`[FEEDBACK-LOOP] Received for BigQuery: ${data.shipment_id}`);
    
    // Logic to calculate error: Predicted vs Actual
    // Then log to BigQuery (simulated here)
    message.ack();
  });

  subscription.on('error', error => {
    console.error('[PUBSUB SUB ERROR]:', error);
  });
};
