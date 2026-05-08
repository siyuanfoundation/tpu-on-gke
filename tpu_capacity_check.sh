for ZONE in us-south1-a europe-west4-a us-central1-a us-east5-c; do
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
