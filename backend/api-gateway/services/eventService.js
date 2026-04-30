import { PubSub } from '@google-cloud/pubsub';
import { BigQuery } from '@google-cloud/bigquery';

const pubsub = new PubSub();
const bigquery = new BigQuery();

const TOPIC_NAME = process.env.PUBSUB_TOPIC || 'logistics-events';
const BQ_DATASET = 'logistics_analytics';
const BQ_TABLE = 'events_stream';

class EventManager {
  /**
   * Publish asynchronous event to Google Cloud Pub/Sub
   */
  async publishEvent(eventType, data) {
    const payload = { eventType, data, timestamp: new Date().toISOString() };
    const dataBuffer = Buffer.from(JSON.stringify(payload));

    try {
      const messageId = await pubsub.topic(TOPIC_NAME).publishMessage({
        data: dataBuffer,
        attributes: { eventType },
        orderingKey: data.shipment_id || 'default'
      });
      console.log(`[PUBSUB] Event ${eventType} published. ID: ${messageId}`);
    } catch (err) {
      console.error(`[PUBSUB ERROR] Failed to publish event: ${err.message}`);
      throw err;
    }
  }

  /**
   * Stream analytics to BigQuery (OLAP) instead of Firestore (OLTP)
   */
  async logToBigQuery(shipmentId, eventType, details = {}) {
    try {
      const row = {
        shipment_id: shipmentId,
        event_type: eventType,
        details: JSON.stringify(details),
        timestamp: bigquery.datetime(new Date().toISOString())
      };
      await bigquery.dataset(BQ_DATASET).table(BQ_TABLE).insert([row]);
    } catch (err) {
      // Don't throw, just log. Analytics shouldn't break operations.
      console.error(`[BIGQUERY ERROR] Insert failed:`, err);
    }
  }
}

export const eventManager = new EventManager();
