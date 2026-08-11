#!/bin/bash

# Configuration Constants
GPU_ACCELERATOR_NAME="${GPU_ACCELERATOR_NAME:-nvidia-l4}"
GPU_MACHINE_TYPE="${GPU_MACHINE_TYPE:-g2-standard-4}"

readarray -t ZONES < <(gcloud compute accelerator-types list --filter="name='$GPU_ACCELERATOR_NAME'" --format="value(zone)" 2>/dev/null)

for ZONE in "${ZONES[@]}"; do
  echo "Checking $ZONE..."
  if gcloud compute instances create "check-$ZONE" \
    --zone="$ZONE" \
    --machine-type="$GPU_MACHINE_TYPE" \
    --provisioning-model=SPOT \
    --quiet 2>&1 | grep -q "Created"; then
      echo "SUCCESS: Capacity found in $ZONE"
      gcloud compute instances delete "check-$ZONE" --zone="$ZONE" --quiet
      break
  else
      echo "FAIL: No capacity in $ZONE"
  fi
done
