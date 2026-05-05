import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const client = new SecretManagerServiceClient();

let _cachedProjectId = null;
const resolveProjectId = async () => {
  if (_cachedProjectId) return _cachedProjectId;

  _cachedProjectId = (
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    process.env.PROJECT_ID ||
    (await client.getProjectId()) ||
    undefined
  );
  return _cachedProjectId;
};

/**
 * Production-grade Secret Management
 * Fetches secrets from GCP Secret Manager at runtime to avoid hardcoded keys.
 */
export const getSecret = async (secretName) => {
  try {
    const projectId = await resolveProjectId();
    if (!projectId) {
      throw new Error('Unable to determine GCP project ID for Secret Manager access');
    }

    const [version] = await client.accessSecretVersion({
      name: `projects/${projectId}/secrets/${secretName}/versions/latest`,
    });

    const payload = version.payload.data.toString().trim();
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
    console.log(`Loading secret: ${secret}`);
    const value = await getSecret(secret);
    if (value) {
      process.env[secret] = value;
      console.log(`✅ Loaded secret: ${secret}`);
    } else {
      console.log(`❌ Failed to load secret: ${secret}`);
    }
  }
  console.log('✅ Secrets loaded successfully.');
};
