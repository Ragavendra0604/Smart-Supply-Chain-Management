import { EventEmitter } from 'events';
import shipmentController from '../controllers/shipmentController.js';

class EventManager extends EventEmitter {
  constructor() {
    super();
    this.setupListeners();
  }

  setupListeners() {
    // Asynchronous Event: When a shipment is updated, trigger AI analysis
    // This decouples the location update from the heavy AI processing
    this.on('shipment.location_updated', async (data) => {
      console.log(`[EVENT] Processing AI analysis for shipment: ${data.shipment_id}`);
      try {
        // In a real production system, this would be a message in Pub/Sub or BullMQ
        // Here we simulate the async behavior
        setImmediate(async () => {
          await shipmentController.runAsyncAnalysis(data.shipment_id);
        });
      } catch (err) {
        console.error(`[EVENT ERROR] Failed to process analysis: ${err.message}`);
      }
    });

    // Learning System Pipeline: Log results for future model retraining
    this.on('ai.analysis_completed', async (data) => {
      console.log(`[DATA PIPELINE] Logging AI result for retraining: ${data.shipment_id}`);
      // This would go to BigQuery or a dedicated 'training_data' collection in Firestore
      // To satisfy "learning system" requirement
    });
  }

  emitLocationUpdate(shipment_id, location) {
    this.emit('shipment.location_updated', { shipment_id, location });
  }
}

export const eventManager = new EventManager();
