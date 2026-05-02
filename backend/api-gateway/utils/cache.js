const cache = new Map();

/**
 * Simple TTL Cache Utility
 */
export const cacheManager = {
  get: (key) => {
    const entry = cache.get(key);
    if (!entry) return null;
    
    if (Date.now() > entry.expiry) {
      cache.delete(key);
      return null;
    }
    return entry.value;
  },

  set: (key, value, ttlMs = 600000) => {
    cache.set(key, {
      value,
      expiry: Date.now() + ttlMs
    });
  },

  delete: (key) => {
    cache.delete(key);
  },

  clear: () => {
    cache.clear();
  }
};
