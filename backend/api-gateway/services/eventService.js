import { PubSub } from '@google-cloud/pubsub';
import { BigQuery } from '@google-cloud/bigquery';

const pubsub = new PubSub();
const bigquery = new BigQuery();

const TOPIC_NAME = process.env.PUBSUB_TOPIC || 'logistics-events';
const BQ_DATASET = 'logistics_analytics';
const BQ_TABLE = 'events_stream';

// --- BIGQUERY BATCHING CONFIG ---
const BQ_BATCH_SIZE = 50; // Rows per insert
const BQ_BATCH_TIMEOUT = 10000; // 10 seconds
let bqBuffer = [];
let bqTimer = null;

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
   * Stream analytics to BigQuery (OLAP) with Batching to reduce costs
   */
  async logToBigQuery(shipmentId, eventType, details = {}) {
    const row = {
      shipment_id: shipmentId,
      event_type: eventType,
      details: JSON.stringify(details),
      timestamp: bigquery.datetime(new Date().toISOString())
    };

    bqBuffer.push(row);

    if (bqBuffer.length >= BQ_BATCH_SIZE) {
      await this.flushBigQuery();
    } else if (!bqTimer) {
      bqTimer = setTimeout(() => this.flushBigQuery(), BQ_BATCH_TIMEOUT);
    }
  }

  async flushBigQuery() {
    if (bqBuffer.length === 0) return;

    const rowsToInsert = [...bqBuffer];
    bqBuffer = [];
    if (bqTimer) {
      clearTimeout(bqTimer);
      bqTimer = null;
    }

    try {
      await bigquery.dataset(BQ_DATASET).table(BQ_TABLE).insert(rowsToInsert);
      console.log(`[BIGQUERY] Flushed ${rowsToInsert.length} rows to analytics.`);
    } catch (err) {
      console.error(`[BIGQUERY ERROR] Batch insert failed:`, JSON.stringify(err.errors || err));
    }
  }
}

export const eventManager = new EventManager();
