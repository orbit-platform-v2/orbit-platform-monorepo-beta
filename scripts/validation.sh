#!/bin/bash

echo "🔍 Validating 50 vCPU Budget Compliance"
echo "======================================"

# Read Terraform variables
PROJECT_ID=$(grep 'project_id' infrastructure/terraform/terraform.tfvars | cut -d'"' -f2)
CLUSTER_NAME=$(grep 'cluster_name' infrastructure/terraform/terraform.tfvars | cut -d'"' -f2)
REGION=$(grep 'region' infrastructure/terraform/terraform.tfvars | cut -d'"' -f2)

echo "Project: $PROJECT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# Check current node configuration
echo "📊 Current Node Configuration:"
gcloud container clusters describe $CLUSTER_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="table(nodePools[].name,nodePools[].config.machineType,nodePools[].initialNodeCount,nodePools[].autoscaling.maxNodeCount)" 2>/dev/null

# Calculate total potential CPU
echo ""
echo "🧮 CPU Calculation:"

# Get node pools info
NODE_POOLS=$(gcloud container clusters describe $CLUSTER_NAME \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(nodePools[].name)" 2>/dev/null)

TOTAL_CPU=0
for pool in $NODE_POOLS; do
  MACHINE_TYPE=$(gcloud container clusters describe $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(nodePools[].config.machineType)" \
    --filter="nodePools.name=$pool" 2>/dev/null)
  
  MAX_NODES=$(gcloud container clusters describe $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --format="value(nodePools[].autoscaling.maxNodeCount)" \
    --filter="nodePools.name=$pool" 2>/dev/null)
  
  # Get vCPU per machine type
  case $MACHINE_TYPE in
    *e2-standard-2*) CPU_PER_NODE=2 ;;
    *e2-standard-4*) CPU_PER_NODE=4 ;;
    *e2-standard-8*) CPU_PER_NODE=8 ;;
    *e2-standard-16*) CPU_PER_NODE=16 ;;
    *) CPU_PER_NODE=4 ;; # Default assumption
  esac
  
  POOL_MAX_CPU=$((MAX_NODES * CPU_PER_NODE))
  TOTAL_CPU=$((TOTAL_CPU + POOL_MAX_CPU))
  
  echo "  $pool: $MAX_NODES × $MACHINE_TYPE = $POOL_MAX_CPU vCPU"
done

echo ""
echo "💰 Budget Analysis:"
echo "  Maximum possible CPU: $TOTAL_CPU vCPU"
echo "  Budget limit: 50 vCPU"

if [ $TOTAL_CPU -le 50 ]; then
  echo "  Status: ✅ WITHIN BUDGET (${TOTAL_CPU}/50 vCPU)"
  echo "  Available headroom: $((50 - TOTAL_CPU)) vCPU"
else
  echo "  Status: ❌ EXCEEDS BUDGET (${TOTAL_CPU}/50 vCPU)"
  echo "  Over budget by: $((TOTAL_CPU - 50)) vCPU"
  echo ""
  echo "🚨 RECOMMENDATIONS:"
  echo "  - Reduce auto_scaling_max values"
  echo "  - Use smaller machine types"
  echo "  - Implement stricter resource quotas"
fi

echo ""
echo "🎯 Recommended Configuration for 50 vCPU:"
echo "  System pool: 2 × e2-standard-2 = 4 vCPU"
echo "  Challenge pool: 11 × e2-standard-4 = 44 vCPU" 
echo "  Total: 48 vCPU (2 vCPU buffer)"