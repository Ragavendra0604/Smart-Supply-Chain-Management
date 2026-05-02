import express from 'express';
import shipmentController from '../controllers/shipmentController.js';

const router = express.Router();

router.post('/analyze', shipmentController.analyzeShipment);
router.post('/simulate', shipmentController.simulateShipment);

export default router;