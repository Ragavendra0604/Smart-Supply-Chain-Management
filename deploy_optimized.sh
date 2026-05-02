#!/bin/bash
# PRODUCTION DEPLOYMENT SCRIPT (COST OPTIMIZED)
# Use this to deploy your API Gateway to Cloud Run with Staff Engineer settings.

SERVICE_NAME="smart-supply-chain-api"
REGION="us-central1"
PROJECT_ID=$(gcloud config get-value project)

echo "🚀 Deploying $SERVICE_NAME to $REGION..."

gcloud run deploy $SERVICE_NAME \
  --source ./backend/api-gateway \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 2 \
  --cpu 0.5 \
  --memory 256MiB \
  --concurrency 80 \
  --no-cpu-throttling=false \
  --labels=environment=production,cost-center=mvp

echo "✅ Deployment Complete."
echo "💰 Optimization Applied:"
echo "   - CPU Throttling: ENABLED (Only pay during requests)"
echo "   - Instance Cap: 2 (Prevents billing spikes)"
echo "   - CPU/Mem: 0.5 vCPU / 256MiB (Minimal footprint)"
