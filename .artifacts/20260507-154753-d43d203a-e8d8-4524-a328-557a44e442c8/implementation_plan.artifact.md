# System Audit & Stabilization Plan

This plan addresses critical security gaps, ML prediction inconsistencies, and UI stability issues discovered during the audit.

## User Review Required

- **ML Feature Mapping**: I've derived a mapping for `weather_condition` (1=Clear, 2=Cloudy, 3=Rain, 4=Storm) based on the synthetic dataset. Please confirm if this matches the training logic.
- **Simulator Auth**: Adding `authMiddleware` to simulator controls might break existing automated scripts if they don't provide a Bearer token or the `x-simulator-secret`.

## Proposed Changes

### Backend: API Gateway

Stabilize security and CORS configuration.

#### [index.js](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/backend/api-gateway/index.js)

- Apply `authMiddleware` to `/api/simulator/start`, `/api/simulator/stop`, and `/api/system/status`.
- Add `X-Trace-Id` to `allowedHeaders` in CORS options.

#### [security.js](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/backend/api-gateway/utils/security.js)

- Update `corsOptions.allowedHeaders` to include `X-Trace-Id`.

---

### Backend: AI Service (Python)

Fix ML feature mismatch and OIDC validation.

#### [main.py](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/backend/ai-service/main.py)

- Update `id_token.verify_oauth2_token` to verify the `audience` (typically the service URL in Cloud Run).

#### [logistics_service.py](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/backend/ai-service/app/services/logistics_service.py)

- Fix `get_ml_delay_prediction` to use features matching the `RandomForestRegressor` model:
    - `traffic_level`: Map from [0.0, 1.0] to [1, 4].
    - `weather_condition`: Map strings ("Clear", "Rain", etc.) to numeric codes [1, 4].
    - `distance_km`: Preserve.
    - `time_of_day`: Use `datetime.now().hour`.
    - `day_of_week`: Use `datetime.now().weekday()`.
- Ensure column order in `pd.DataFrame` matches `['traffic_level', 'weather_condition', 'distance_km', 'time_of_day', 'day_of_week']`.

---

### Frontend: Flutter

Fix UI theme inconsistencies and infinite loops.

#### [api_service.dart](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/frontend/lib/services/api_service.dart)

- Update `stopBackendSimulator` to send `{}` instead of `null` body when `shipmentId` is null.

#### [dashboard_screen.dart](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/frontend/lib/modules/dashboard/dashboard_screen.dart)

- Fix `_checkAndShowWalkthrough` infinite loop by adding a check for `recentShipments.isEmpty` after bootstrapping is complete.
- Replace `AppTheme.light.textTheme` usages with `Theme.of(context).textTheme`.

#### [details_screen.dart](file:///D:/Solution_Build_2026/MVP/smart_supply_chain_management_mvp_v3/frontend/lib/modules/details/details_screen.dart)

- Replace `AppTheme.light.textTheme` with `Theme.of(context).textTheme`.

## Verification Plan

### Automated Tests
- Run `backend/test_system.py` if available (need to check content).
- Run the model inspection script `inspect_model.py` again to confirm features.

### Manual Verification
- **Security**: Attempt to call `/api/simulator/start` without an Auth header and confirm it returns 401.
- **ML**: Trigger a shipment analysis and verify logs show the corrected feature vector being passed to the model.
- **UI**: Check dashboard walkthrough on an empty shipment list and ensure it doesn't loop.
- **Theme**: Toggle system dark mode (if possible) or verify theme usage is correct via code inspection.
