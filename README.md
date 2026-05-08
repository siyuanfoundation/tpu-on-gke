# tpu-on-gke

Before you start, check for TPU availability in a particular region
```bash
gcloud compute accelerator-types list --filter="name='tpu-v5-litepod'" --format="value(zone)"

bash ./tpu_capacity_check.sh
```

## Create a GKE cluster
1. Set up variables
```bash
export ZONE="us-south1-a"
export PROJECT_ID="${USER}-gke-dev"
export CLUSTER_NAME="${USER}-tpu-${ZONE}"
```

2. Create a standard cluster with RayOperator and GcsFuseCsiDriver addons (optional)
```bash
gcloud container clusters create $CLUSTER_NAME \
  --addons=RayOperator,GcsFuseCsiDriver \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --machine-type=n2-standard-16 \
  --location=$ZONE \
  --enable-image-streaming \
  --project=$PROJECT_ID
```

3. Connect kubectl to your newly created GKE cluster
```bash
gcloud container clusters get-credentials $CLUSTER_NAME --location $ZONE --project $PROJECT_ID
```

4. Create TPU Node Pool

You can Create a CCC to request a specific TPU topology (e.g., v5e 2x4).

```bash
kubectl apply -f tpu-compute-class.yaml

# Test with a TPU job
kubectl apply -f tpu-job-ccc.yaml
```

Or manually create a TPU Node Pool
```bash
# create a spot node pool
gcloud container node-pools create tpu-v5-single-host-spot \
  --location=$ZONE \
  --cluster=$CLUSTER_NAME \
  --spot \
  --num-nodes=1 \
  --reservation-affinity=none \
  --machine-type=ct5lp-hightpu-8t \
  --project=$PROJECT_ID

# Test with a TPU job
kubectl apply -f tpu-job.yaml
```
