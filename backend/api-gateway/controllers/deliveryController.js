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

    // --- ROBUST DISTANCE EXTRACTION ---
    // Priority: AI-processed distance_km → raw distance_meters → text parse → aiResponse routes
    let distanceKm = 0;
    if (routeData.distance_km > 0) {
      // Python AI service already converted to km
      distanceKm = parseFloat(routeData.distance_km);
    } else if (routeData.distance_meters > 0) {
      // Raw Google Maps value (always present)
      distanceKm = parseFloat((routeData.distance_meters / 1000).toFixed(2));
    } else if (routeData.distance && typeof routeData.distance === 'string') {
      // e.g. "142 km" or "142.5 km" or "890 m"
      const distMatch = routeData.distance.match(/([\d,.]+)\s*(km|m)/i);
      if (distMatch) {
        const val = parseFloat(distMatch[1].replace(',', ''));
        distanceKm = distMatch[2].toLowerCase() === 'm' ? val / 1000 : val;
      }
    }
    // Last resort: check AI-processed all_routes inside aiResponse
    if (distanceKm === 0 && aiResponse.all_routes?.length > 0) {
      const bestRoute = aiResponse.all_routes.find(r => r.is_recommended) ?? aiResponse.all_routes[0];
      distanceKm = parseFloat(bestRoute.distance_km || 0);
    }
    distanceKm = parseFloat(distanceKm.toFixed(2));

    // --- OTHER TELEMETRY FIELDS ---
    // --- OTHER TELEMETRY FIELDS ---
    const rawTravelTimeMin = routeData.travel_time_min;
    const rawDurationSec   = routeData.duration_seconds;
    const plannedMin = parseFloat(
      rawTravelTimeMin != null ? rawTravelTimeMin
      : rawDurationSec != null ? rawDurationSec / 60
      : 0
    );
    const totalCost = parseFloat(routeData.total_cost ?? aiResponse.optimization_data?.after?.cost ?? 0);
    const totalFuel = parseFloat(routeData.total_fuel ?? aiResponse.optimization_data?.after?.fuel ?? 0);
    const peakRiskScore = parseFloat(aiResponse.risk_score ?? 0);
    const weather = (data.weatherData || {}).condition || 'Clear';
    const newsDisruptions = (data.newsData || []).length;

    console.log(`[DELIVERY] ${shipment_id} telemetry: distanceKm=${distanceKm}, plannedMin=${plannedMin}, source=${routeData.source || 'stored'}`);


    // Actual duration: prefer simulation_started_at (stamped when sim begins)
    // Fallback to created_at. Cap at 24h to avoid outliers for long-idle shipments.
    const simStartedAt = data.simulation_started_at?.toDate?.() ?? null;
    const createdAt = data.created_at?.toDate?.() ?? new Date();
    const startRef = simStartedAt ?? createdAt;
    const elapsedMs = Math.min(Date.now() - startRef.getTime(), 86400 * 1000);
    let actualMin = Math.max(1, Math.round(elapsedMs / 60000));

    // MVP FIX: Handle Simulator Fast-Forward
    // If the simulation finished unrealistically fast (< 10% of planned time), calculate the "simulated" actual time.
    if (elapsedMs < (plannedMin * 60000 * 0.1) && plannedMin > 0) {
      const weatherCond = (data.weatherData || {}).condition?.toLowerCase() || '';
      let envModifier = 1.0;
      if (weatherCond.includes('rain') || weatherCond.includes('snow') || weatherCond.includes('storm')) {
        envModifier *= 0.75;
      }
      if (aiResponse.risk_level === 'HIGH') {
        envModifier *= 0.80;
      }
      const injectedModifier = data.simulation_speed_modifier || 1.0;
      const totalModifier = envModifier * injectedModifier;
      
      // Calculate deterministic actual time without random variance
      actualMin = Math.round(plannedMin / totalModifier);
    }

    // Average speed estimation: distance / actual trip time
    const avgSpeedKmH = (distanceKm > 0 && actualMin > 0)
      ? parseFloat(((distanceKm / actualMin) * 60).toFixed(1))
      : 0;

    // 3. Call AI Service for the delivery summary
    const summaryPayload = {
      shipment_id,
      origin: data.origin || 'Unknown',
      destination: data.destination || 'Unknown',
      mode: data.vehicle_type || data.mode || 'ROAD',
      cargo_type: data.cargo_type || 'General',
      priority: data.priority || 'Normal',
      is_perishable: data.is_perishable || false,
      distance_km: distanceKm,
      actual_duration_min: actualMin,
      planned_duration_min: plannedMin,
      total_cost: totalCost,
      total_fuel: totalFuel,
      avg_speed_kmh: avgSpeedKmH,
      peak_risk_score: peakRiskScore,
      weather_encountered: weather,
      delays_mins: Math.max(0, actualMin - plannedMin),
      news_disruptions: newsDisruptions,
      is_simulation: true,
      model_name: 'gemini-2.5-flash',
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

      // Telemetry validation (mirrors Python AI service logic)
      const hasTelemetryIssue = distanceKm === 0 || (avgSpeedKmH === 0 && actualMin > 0);

      let efficiency, grade;
      if (hasTelemetryIssue) {
        // Can't trust distance/speed — grade purely on timing
        efficiency = onTime ? 0.95 : 0.5;
        grade = onTime ? 'A' : 'C';
      } else {
        efficiency = plannedMin > 0
          ? Math.max(0, Math.min(1, 1 - Math.abs(delayVariance) / plannedMin))
          : (onTime ? 1 : 0.6);
        grade = efficiency >= 0.90 ? 'A' : efficiency >= 0.75 ? 'B' : efficiency >= 0.55 ? 'C' : 'D';
      }

      // Maintenance: decouple from route risk (peakRiskScore). Only fire on vehicle issues or severe anomalies.
      const vehicleHealth = data.vehicle_health || 'GOOD';
      const maintenanceFlag = !hasTelemetryIssue && (vehicleHealth !== 'GOOD' || efficiency < 0.40);

      deliverySummary = {
        success: true,
        on_time: onTime,
        delay_variance_mins: parseFloat(delayVariance.toFixed(1)),
        efficiency_rating: parseFloat(efficiency.toFixed(3)),
        performance_grade: grade,
        telemetry_quality: hasTelemetryIssue ? 'DEGRADED' : 'VALID',
        summary: `Shipment ${shipment_id} from ${data.origin || 'origin'} to ${data.destination || 'destination'} delivered ${onTime ? 'on time' : `${Math.abs(Math.round(delayVariance))} mins late`}. Grade: ${grade}.`
          + (hasTelemetryIssue ? ' ⚠️ Grade based on timing only — telemetry incomplete.' : ''),
        key_insights: [
          `Delivery was ${onTime ? 'on time ✅' : `${Math.abs(Math.round(delayVariance))} mins late ⚠️`}`,
          `Efficiency: ${(efficiency * 100).toFixed(0)}%`,
          hasTelemetryIssue ? '⚠️ Speed/distance telemetry unavailable' : `Avg speed: ${avgSpeedKmH} km/h`,
          `Peak risk: ${(peakRiskScore * 100).toFixed(0)}%`,
        ],
        maintenance_flag: maintenanceFlag,
        maintenance_reason: maintenanceFlag ? (vehicleHealth !== 'GOOD' ? `Vehicle health reported as ${vehicleHealth}.` : 'Abnormally low efficiency detected. Inspection advised.') : null,
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
          summary: deliverySummary.summary,
          key_insights: deliverySummary.key_insights,
          maintenance_flag: deliverySummary.maintenance_flag,
          maintenance_reason: deliverySummary.maintenance_reason,
          next_shipment_recommendation: deliverySummary.next_shipment_recommendation,
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
