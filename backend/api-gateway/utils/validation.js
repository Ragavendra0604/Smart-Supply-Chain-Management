const isNonEmptyString = (value) =>
  typeof value === 'string' && value.trim().length > 0;

const normalizeString = (value) => value.trim();

const isValidShipmentId = (value) => /^[A-Za-z0-9_-]{3,64}$/.test(value);

export const validateCreateShipment = (body = {}) => {
  const errors = [];
  const shipment_id = isNonEmptyString(body.shipment_id)
    ? normalizeString(body.shipment_id)
    : '';
  const origin = isNonEmptyString(body.origin) ? normalizeString(body.origin) : '';
  const destination = isNonEmptyString(body.destination)
    ? normalizeString(body.destination)
    : '';

  if (!shipment_id) {
    errors.push('shipment_id is required');
  } else if (!isValidShipmentId(shipment_id)) {
    errors.push('shipment_id must be 3-64 characters using letters, numbers, dash, or underscore');
  }

  if (!origin) errors.push('origin is required');
  if (!destination) errors.push('destination is required');

  return {
    valid: errors.length === 0,
    errors,
    value: {
      shipment_id,
      origin,
      destination
    }
  };
};

export const validateShipmentLookup = (shipment_id) => {
  const id = isNonEmptyString(shipment_id) ? normalizeString(shipment_id) : '';

  if (!id) {
    return { valid: false, errors: ['shipment_id is required'], value: { shipment_id: id } };
  }

  if (!isValidShipmentId(id)) {
    return {
      valid: false,
      errors: ['shipment_id must be 3-64 characters using letters, numbers, dash, or underscore'],
      value: { shipment_id: id }
    };
  }

  return { valid: true, errors: [], value: { shipment_id: id } };
};

export const validateLocationUpdate = (body = {}) => {
  const lookup = validateShipmentLookup(body.shipment_id);
  const lat = Number(body.lat);
  const lng = Number(body.lng);
  const errors = [...lookup.errors];

  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    errors.push('lat must be a number between -90 and 90');
  }

  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    errors.push('lng must be a number between -180 and 180');
  }

  return {
    valid: errors.length === 0,
    errors,
    value: {
      shipment_id: lookup.value.shipment_id,
      lat,
      lng
    }
  };
};
