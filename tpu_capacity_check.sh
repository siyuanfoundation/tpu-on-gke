#!/usr/bin/env bash

ZONES=(
  europe-west1-b
  europe-west1-c
  us-west1-a
  us-west1-c
  asia-east1-a
  asia-east1-b
  asia-east1-c
  us-east1-b
  us-east1-c
  asia-northeast1-b
  asia-southeast1-b
  us-east4-b
  europe-west3-c
  northamerica-northeast1-b
  europe-west4-b
  europe-west4-a
  europe-north1-c
  europe-north1-a
  us-west4-a
  us-west4-b
  southamerica-west1-c
  us-east7-b
  us-east7-c
  us-east5-c
  us-east5-b
  us-east5-a
  us-south1-a
)

for ZONE in "${ZONES[@]}"; do
  echo "Checking $ZONE..."
  if gcloud compute tpus tpu-vm create "check-$ZONE" \
    --zone="$ZONE" \
    --accelerator-type=v5litepod-8 \
    --version=tpu-vm-tf-2.15.0-pjrt \
    --spot 2>&1 | grep -q "Created"; then
      echo "SUCCESS: Capacity found in $ZONE"
      gcloud compute tpus tpu-vm delete "check-$ZONE" --zone="$ZONE" --quiet
      break
  else
      echo "FAIL: No capacity in $ZONE"
  fi
done
