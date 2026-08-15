#!/usr/bin/env bash

ZONES=(
  us-central1-a
  us-central1-b
  us-central1-c
  us-central2-b
  us-west1-c
  asia-east1-c
  us-east1-d
  asia-northeast1-b
  asia-southeast1-b
  us-east4-a
  us-east4-b
  southamerica-east1-c
  asia-south1-b
  asia-south1-c
  europe-west4-a
  southamerica-west1-a
  us-east7-ai1b
  us-east5-c
  us-east5-b
  us-east5-a
  us-south1-ai1b
  us-west8-a
)

for ZONE in "${ZONES[@]}"; do
  echo "Checking $ZONE..."
  if gcloud compute tpus tpu-vm create "check-$ZONE" \
    --zone="$ZONE" \
    --accelerator-type=v6e-8 \
    --version=tpu-vm-tf-2.15.0-pjrt \
    --spot 2>&1 | grep -q "Created"; then
      echo "SUCCESS: Capacity found in $ZONE"
      gcloud compute tpus tpu-vm delete "check-$ZONE" --zone="$ZONE" --quiet
      break
  else
      echo "FAIL: No capacity in $ZONE"
  fi
done
