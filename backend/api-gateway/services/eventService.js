import { EventEmitter } from 'events';
import shipmentController from '../controllers/shipmentController.js';
import { processIdempotentEvent } from '../utils/idempotency.js';
import { db } from '../config/firebase.js';

class EventManager extends EventEmitter {
  constructor() {
    super();
    this.setupListeners();
  }

  setupListeners() {
    /**
     * PRODUCTION PATTERN: Idempotent Event Processing
     * This listener handles location updates asynchronously.
     * It ensures that even if the same event is received multiple times (Pub/Sub retry),
     * it is only processed once.
     */
    this.on('shipment.location_updated', async (data) => {
      const eventId = `loc_${data.shipment_id}_${Date.now()}`; // In prod, use a unique event UUID from Pub/Sub
      
      console.log(`[EVENT PIPELINE] Received location update for ${data.shipment_id}`);

      try {
        await processIdempotentEvent(eventId, async () => {
          // 1. Run AI Analysis
          await shipmentController.runAsyncAnalysis(data.shipment_id);
          
          // 2. Log to BigQuery / Learning Loop (Simulated)
          await this.logToDataPipeline(data.shipment_id, 'LOCATION_UPDATE');
          
          return { status: 'ANALYZED' };
        });
      } catch (err) {
        console.error(`[PIPELINE ERROR] Failed to process ${data.shipment_id}: ${err.message}`);
        // In prod, this would automatically trigger a Pub/Sub NACK for retry
      }
    });

    this.on('ai.analysis_completed', async (data) => {
      console.log(`[DATA PIPELINE] Logging AI result for retraining: ${data.shipment_id}`);
      await this.logToDataPipeline(data.shipment_id, 'AI_ANALYSIS_COMPLETE');
    });
  }

  async logToDataPipeline(shipmentId, eventType) {
    // Simulated BigQuery / Analytics ingestion
    // In production, this would use @google-cloud/bigquery
    const entry = {
      shipment_id: shipmentId,
      event: eventType,
      timestamp: new Date().toISOString()
    };
    
    await db.collection('analytics_stream').add(entry);
  }

  emitLocationUpdate(shipment_id, location) {
    this.emit('shipment.location_updated', { shipment_id, location });
  }
}

export const eventManager = new EventManager();
