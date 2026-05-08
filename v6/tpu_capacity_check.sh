gcloud compute accelerator-types list --filter="name='tpu-v6e'" --format="value(zone)"

for ZONE in us-central1-b us-central1-a us-east5-a; do
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
