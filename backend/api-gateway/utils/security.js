const requestBuckets = new Map();

// Cleanup expired buckets every 5 minutes to prevent memory leak
setInterval(() => {
  const now = Date.now();
  let cleaned = 0;
  for (const [key, bucket] of requestBuckets.entries()) {
    if (now > bucket.resetAt + 300000) { // Keep 5 minutes beyond reset for safety
      requestBuckets.delete(key);
      cleaned++;
    }
  }
  if (cleaned > 0) {
    console.log(`[RATE LIMITER] Cleaned ${cleaned} expired rate limit buckets`);
  }
}, 300000); // 5 minutes

const parseAllowedOrigins = () => {
  const raw = process.env.ALLOWED_ORIGINS ||
    'http://localhost:3000,http://localhost:5000,http://localhost:5173,https://ssm-sb.web.app,https://ssm-sb.firebaseapp.com';
  return raw
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
};

export const corsOptions = {
  origin(origin, callback) {
    // If no origin (e.g. mobile apps or server-side calls), allow it
    if (!origin) return callback(null, true);

    const allowedOrigins = parseAllowedOrigins();

    // Check if origin matches localhost (any port) or 127.0.0.1
    const isLocalhost = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);

    if (isLocalhost || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      console.warn(`[CORS REJECTED] Origin: ${origin}`);
      // Don't throw Error, just deny headers by passing null, false
      callback(null, false);
    }
  },
  methods: ['GET', 'POST', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-idempotency-key', 'X-Trace-Id'],
  maxAge: 600
};

export const securityHeaders = (req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), camera=(), microphone=()');
  next();
};

export const rateLimiter = (req, res, next) => {
  const windowMs = Number(process.env.RATE_LIMIT_WINDOW_MS || 60_000);
  const maxRequests = Number(process.env.RATE_LIMIT_MAX || 120);
  const key = req.ip || req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  let bucket = requestBuckets.get(key);
  
  // CRITICAL FIX: Initialize or reset bucket
  if (!bucket || now > bucket.resetAt) {
    bucket = { count: 0, resetAt: now + windowMs };
  }

  bucket.count += 1;
  requestBuckets.set(key, bucket);

  if (bucket.count > maxRequests) {
    // CRITICAL FIX: Include retry-after header for 429 responses
    const retryAfterSeconds = Math.ceil((bucket.resetAt - now) / 1000);
    res.setHeader('Retry-After', retryAfterSeconds.toString());
    res.status(429).json({
      success: false,
      error: 'Too many requests. Please retry shortly.',
      retryAfter: retryAfterSeconds
    });
    return;
  }

  next();
};
