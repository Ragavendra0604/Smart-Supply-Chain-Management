import { PubSub } from '@google-cloud/pubsub';
import { BigQuery } from '@google-cloud/bigquery';

let pubsub;
let bigquery;

try {
  pubsub = new PubSub();
  bigquery = new BigQuery();
} catch (e) {
  console.error('[EVENT SERVICE] Cloud SDK Initialization Failed:', e.message);
}

const TOPIC_NAME = process.env.PUBSUB_TOPIC || 'logistics-events';
const BQ_DATASET = 'logistics_analytics';
const BQ_TABLE = 'events_stream';

// --- BIGQUERY BATCHING CONFIG (FINOPS OPTIMIZED) ---
const BQ_BATCH_SIZE = 100; // Increased for higher throughput
const BQ_BATCH_TIMEOUT = 60000; // 60 seconds (reduces streaming overhead)
let bqBuffer = [];
let bqTimer = null;
let flushInProgress = false;

class EventManager {
  constructor() {
    // PRODUCTION SRE: Handle Cloud Run lifecycle events
    process.on('SIGTERM', async () => {
      console.log('[SYSTEM] SIGTERM received. Draining BigQuery buffer...');
      await this.flushBigQuery();
      // No process.exit(0) here, let Cloud Run handle it after draining
    });
  }

  /**
   * Publish asynchronous event to Google Cloud Pub/Sub
   */
  async publishEvent(eventType, data) {
    if (!pubsub) {
      console.warn(`[PUBSUB SKIP] Service not initialized for ${eventType}`);
      return;
    }

    const payload = { eventType, data, timestamp: new Date().toISOString() };
    const dataBuffer = Buffer.from(JSON.stringify(payload));

    try {
      await pubsub.topic(TOPIC_NAME).publishMessage({
        data: dataBuffer,
        attributes: { eventType },
        orderingKey: (data.shipment_id || 'default').toString()
      });
    } catch (err) {
      console.error(`[PUBSUB ERROR] Failed to publish event: ${err.message}`);
    }
  }

  /**
   * Stream analytics to BigQuery (OLAP) with Batching to reduce costs
   */
  async logToBigQuery(shipmentId, eventType, details = {}) {
    if (!bigquery) return;

    try {
      const row = {
        shipment_id: shipmentId,
        event_type: eventType,
        details: JSON.stringify(details),
        timestamp: bigquery.datetime(new Date().toISOString().replace('Z', ''))
      };

      bqBuffer.push(row);

      if (bqBuffer.length >= BQ_BATCH_SIZE) {
        await this.flushBigQuery();
      } else if (!bqTimer) {
        // PRODUCTION SRE: Wrap background timer in a catchable wrapper to avoid unhandled rejections
        bqTimer = setTimeout(() => {
          this.flushBigQuery().catch(err => {
            console.error('[BIGQUERY BACKGROUND FLUSH ERROR]', err.message);
          });
        }, BQ_BATCH_TIMEOUT);
      }
    } catch (e) {
      console.error('[BIGQUERY BUFFER ERROR]', e.message);
    }
  }

  async flushBigQuery() {
    if (!bigquery || bqBuffer.length === 0 || flushInProgress) return;

    flushInProgress = true;
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

      // PRODUCTION SRE: Filter out "poison pill" rows that failed repeatedly
      const retryableRows = rowsToInsert
        .map(row => ({ ...row, retry_count: (row.retry_count || 0) + 1 }))
        .filter(row => {
          if (row.retry_count > 3) {
            console.error(`[BIGQUERY FATAL] Discarding poison pill row after 3 retries: ${row.shipment_id} - ${row.event_type}`);
            return false;
          }
          return true;
        });

      if (retryableRows.length > 0) {
        bqBuffer = [...retryableRows, ...bqBuffer];
      }
    } finally {
      flushInProgress = false;
    }
  }
}

export const eventManager = new EventManager();
