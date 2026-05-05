import { db } from '../config/firebase.js';
import aiService from '../services/aiService.js';
import { eventManager } from '../services/eventService.js';

/**
 * POST /api/shipments/:shipment_id/complete
 *
 * Called by the Flutter frontend the moment the simulation detects DELIVERED.
 * Responsibilities:
 *   1. Validate the shipment exists and is in a completable state.
 *   2. Build the telemetry payload from stored Firestore data.
 *   3. Call AI Service /delivery-summary (which persists + returns the report).
 *   4. Flush a BigQuery telemetry event for analytics.
 *   5. Return the full delivery summary to the frontend.
 */
export const completeDelivery = async (req, res) => {
  const { shipment_id } = req.params;

  if (!shipment_id) {
    return res.status(400).json({ success: false, message: 'shipment_id is required' });
  }

  try {
    // 1. Fetch shipment record
    const docRef = db().collection('shipments').doc(shipment_id);
    const doc = await docRef.get();

    if (!doc.exists) {
      return res.status(404).json({ success: false, message: 'Shipment not found' });
    }

    const data = doc.data();

    // Guard: already delivered — return cached summary if available
    if (data.status === 'DELIVERED' && data.delivery_summary) {
      return res.json({
        success: true,
        already_delivered: true,
        summary: data.delivery_summary,
        delivered_at: data.delivered_at?.toDate?.()?.toISOString() ?? null,
      });
    }

    // 2. Extract telemetry from stored Firestore fields
    const routeData = Array.isArray(data.routeData) ? data.routeData[0] : (data.routeData || {});
    const aiResponse = data.aiResponse || {};

    const distanceKm      = parseFloat(routeData.distance_km || 0);
    const plannedMin      = parseFloat(routeData.travel_time_min || routeData.duration_seconds / 60 || 0);
    const totalCost       = parseFloat(routeData.total_cost || aiResponse.optimization_data?.after?.cost || 0);
    const totalFuel       = parseFloat(routeData.total_fuel || aiResponse.optimization_data?.after?.fuel || 0);
    const peakRiskScore   = parseFloat(aiResponse.risk_score || 0);
    const weather         = (data.weatherData || {}).condition || 'Clear';
    const newsDisruptions = (data.newsData || []).length;

    // Actual duration: use createdAt → now (capped at 24h to avoid outliers)
    const createdAt = data.created_at?.toDate?.() ?? new Date();
    const elapsedMs = Math.min(Date.now() - createdAt.getTime(), 86400 * 1000);
    const actualMin = Math.round(elapsedMs / 60000);

    // Average speed estimation: distance / actual time
    const avgSpeedKmH = actualMin > 0 ? parseFloat(((distanceKm / actualMin) * 60).toFixed(1)) : 0;

    // 3. Call AI Service for the delivery summary
    const summaryPayload = {
      shipment_id,
      origin:              data.origin || 'Unknown',
      destination:         data.destination || 'Unknown',
      mode:                data.vehicle_type || data.mode || 'ROAD',
      cargo_type:          data.cargo_type || 'General',
      priority:            data.priority || 'Normal',
      is_perishable:       data.is_perishable || false,
      distance_km:         distanceKm,
      actual_duration_min: actualMin,
      planned_duration_min: plannedMin,
      total_cost:          totalCost,
      total_fuel:          totalFuel,
      avg_speed_kmh:       avgSpeedKmH,
      peak_risk_score:     peakRiskScore,
      weather_encountered: weather,
      delays_mins:         Math.max(0, actualMin - plannedMin),
      news_disruptions:    newsDisruptions,
      model_name:          'gemini-2.5-flash',
    };

    const aiBaseUrl = process.env.AI_SERVICE_URL || '';
    let deliverySummary = null;

    if (aiBaseUrl) {
      try {
        // Re-use the same authenticated client — but hit /delivery-summary, not /predict
        const { GoogleAuth } = await import('google-auth-library');
        const auth = new GoogleAuth();
        const summaryUrl = aiBaseUrl.replace(/\/predict$/, '') + '/delivery-summary';
        const audience = new URL(summaryUrl).origin;
        const client = await auth.getIdTokenClient(audience);

        const response = await client.request({
          url: summaryUrl,
          method: 'POST',
          data: summaryPayload,
          headers: { 'Content-Type': 'application/json' },
          timeout: 30000,
        });
        deliverySummary = response.data;
      } catch (aiErr) {
        console.error(`[DELIVERY] AI summary call failed: ${aiErr.message}. Using heuristic fallback.`);
      }
    }

    // Heuristic fallback if AI service is unavailable
    if (!deliverySummary) {
      const delayVariance = actualMin - plannedMin;
      const onTime = delayVariance <= 5;
      const efficiency = plannedMin > 0
        ? Math.max(0, Math.min(1, 1 - Math.abs(delayVariance) / plannedMin))
        : (onTime ? 1 : 0.6);
      const grade = efficiency >= 0.90 ? 'A' : efficiency >= 0.75 ? 'B' : efficiency >= 0.55 ? 'C' : 'D';
      const maintenanceFlag = peakRiskScore >= 0.7 || efficiency < 0.55;

      deliverySummary = {
        success: true,
        on_time: onTime,
        delay_variance_mins: parseFloat(delayVariance.toFixed(1)),
        efficiency_rating: parseFloat(efficiency.toFixed(3)),
        performance_grade: grade,
        summary: `Shipment ${shipment_id} from ${data.origin || 'origin'} to ${data.destination || 'destination'} delivered ${onTime ? 'on time' : `${Math.abs(Math.round(delayVariance))} mins late`}. Grade: ${grade}.`,
        key_insights: [
          `Delivery was ${onTime ? 'on time ✅' : `${Math.abs(Math.round(delayVariance))} mins late ⚠️`}`,
          `Efficiency: ${(efficiency * 100).toFixed(0)}%`,
          `Avg speed: ${avgSpeedKmH} km/h`,
          `Peak risk: ${(peakRiskScore * 100).toFixed(0)}%`,
        ],
        maintenance_flag: maintenanceFlag,
        maintenance_reason: maintenanceFlag ? 'High peak risk or low efficiency detected.' : null,
        next_shipment_recommendation: maintenanceFlag
          ? 'Schedule vehicle inspection before next assignment.'
          : 'Vehicle is ready for immediate reassignment.',
        ai_generated: false,
      };

      // Also write DELIVERED state ourselves since AI service didn't do it
      await docRef.set({
        status: 'DELIVERED',
        delivered_at: new Date(),
        updated_at: new Date(),
        delivery_summary: {
          on_time: deliverySummary.on_time,
          delay_variance_mins: deliverySummary.delay_variance_mins,
          efficiency_rating: deliverySummary.efficiency_rating,
          performance_grade: deliverySummary.performance_grade,
          maintenance_flag: deliverySummary.maintenance_flag,
          maintenance_reason: deliverySummary.maintenance_reason,
          ai_generated: false,
          generated_at: new Date(),
        },
      }, { merge: true });
    }

    // 4. BigQuery telemetry event
    eventManager.logToBigQuery(shipment_id, 'SHIPMENT_DELIVERED', {
      origin: data.origin,
      destination: data.destination,
      mode: data.vehicle_type || data.mode || 'ROAD',
      on_time: deliverySummary.on_time,
      performance_grade: deliverySummary.performance_grade,
      efficiency_rating: deliverySummary.efficiency_rating,
      delay_variance_mins: deliverySummary.delay_variance_mins,
      maintenance_flag: deliverySummary.maintenance_flag,
      distance_km: distanceKm,
      total_cost: totalCost,
      total_fuel: totalFuel,
    });

    console.log(`✅ [DELIVERY] ${shipment_id} completed. Grade: ${deliverySummary.performance_grade} | On-time: ${deliverySummary.on_time}`);

    return res.json({
      success: true,
      summary: deliverySummary,
    });

  } catch (err) {
    console.error(`[DELIVERY ERROR] ${err.message}`);
    res.status(500).json({ success: false, error: err.message });
  }
};

export default { completeDelivery };
