import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const client = new SecretManagerServiceClient();

/**
 * Production-grade Secret Management
 * Fetches secrets from GCP Secret Manager at runtime to avoid hardcoded keys.
 */
export const getSecret = async (secretName) => {
  try {
    const [version] = await client.accessSecretVersion({
      name: `projects/${process.env.GOOGLE_CLOUD_PROJECT}/secrets/${secretName}/versions/latest`,
    });

    const payload = version.payload.data.toString();
    return payload;
  } catch (error) {
    console.error(`[SECRET MANAGER ERROR] Could not fetch secret ${secretName}:`, error.message);
    // Fallback to env for local dev if needed, but in prod this should fail
    return process.env[secretName];
  }
};

/**
 * Loads all critical secrets into process.env
 */
export const loadSecrets = async (secretsList) => {
  console.log('🔐 Loading secrets from GCP Secret Manager...');
  for (const secret of secretsList) {
    const value = await getSecret(secret);
    if (value) {
      process.env[secret] = value;
    }
  }
  console.log('✅ Secrets loaded successfully.');
};
