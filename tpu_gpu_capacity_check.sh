#!/bin/bash

# Configuration Constants
TPU_ACCELERATOR_NAME="${TPU_ACCELERATOR_NAME:-tpu-v5-litepod}"
TPU_TYPE="${TPU_TYPE:-v5litepod-8}"
TPU_VERSION="${TPU_VERSION:-tpu-vm-tf-2.15.0-pjrt}"
TPU_QUOTA_METRIC="${TPU_QUOTA_METRIC:-}"

GPU_ACCELERATOR_NAME="${GPU_ACCELERATOR_NAME:-nvidia-l4}"
GPU_MACHINE_TYPE="${GPU_MACHINE_TYPE:-g2-standard-4}"
GPU_QUOTA_METRIC="${GPU_QUOTA_METRIC:-}"

CHECK_QUOTA="${CHECK_QUOTA:-true}"
USE_SPOT="${USE_SPOT:-true}"

PROJECT_FLAG=()
if [[ -n "${PROJECT_ID:-}" ]]; then
  PROJECT_FLAG=(--project="$PROJECT_ID")
fi

echo "=================================================="
echo "Checking accelerator catalog availability & quota..."
echo "TPU: $TPU_ACCELERATOR_NAME ($TPU_TYPE)"
echo "GPU: $GPU_ACCELERATOR_NAME ($GPU_MACHINE_TYPE)"
echo "Check Quotas: $CHECK_QUOTA (Spot: $USE_SPOT)"
echo "=================================================="

# Fetch zones with TPU and GPU accelerator types from catalog
readarray -t RAW_TPU_ZONES < <(gcloud compute accelerator-types list "${PROJECT_FLAG[@]}" --filter="name='$TPU_ACCELERATOR_NAME'" --format="value(zone)" 2>/dev/null | sort -u)
readarray -t RAW_GPU_ZONES < <(gcloud compute accelerator-types list "${PROJECT_FLAG[@]}" --filter="name='$GPU_ACCELERATOR_NAME'" --format="value(zone)" 2>/dev/null | sort -u)

if [[ ${#RAW_TPU_ZONES[@]} -eq 0 ]]; then
  echo "Error: No zones found in catalog offering $TPU_ACCELERATOR_NAME."
  exit 1
fi

if [[ ${#RAW_GPU_ZONES[@]} -eq 0 ]]; then
  echo "Error: No zones found in catalog offering $GPU_ACCELERATOR_NAME."
  exit 1
fi

TPU_ZONES=("${RAW_TPU_ZONES[@]}")
GPU_ZONES=("${RAW_GPU_ZONES[@]}")

# Filter candidate zones by Compute Engine Quota
if [[ "$CHECK_QUOTA" == "true" ]]; then
  echo "Filtering catalog zones by available GCE project quota..."

  QUOTA_OUTPUT=$(python3 - "${TPU_ACCELERATOR_NAME}" "${TPU_TYPE}" "${TPU_QUOTA_METRIC}" "${GPU_ACCELERATOR_NAME}" "${GPU_QUOTA_METRIC}" "${USE_SPOT}" "${PROJECT_ID:-}" <<'EOF'
import json, subprocess, sys

tpu_accel = sys.argv[1]
tpu_type = sys.argv[2]
tpu_quota_override = sys.argv[3]
gpu_accel = sys.argv[4]
gpu_quota_override = sys.argv[5]
use_spot = sys.argv[6].lower() == "true"
project_id = sys.argv[7]

# 1. Determine TPU quota metrics
if tpu_quota_override:
    tpu_metrics = [tpu_quota_override]
elif use_spot:
    if "v5" in tpu_accel or "v5" in tpu_type:
        tpu_metrics = ["PREEMPTIBLE_TPU_LITE_PODSLICE_V5", "PREEMPTIBLE_TPU_LITE_DEVICE_V5"]
    elif "v6" in tpu_accel or "v6" in tpu_type:
        tpu_metrics = ["PREEMPTIBLE_TPU_V6E_PODSLICE", "TPU_V6E_PODSLICE"]
    else:
        tpu_metrics = ["PREEMPTIBLE_TPU_LITE_PODSLICE_V5", "PREEMPTIBLE_TPU_LITE_DEVICE_V5"]
else:
    if "v5" in tpu_accel or "v5" in tpu_type:
        tpu_metrics = ["TPU_LITE_PODSLICE_V5", "TPU_LITE_DEVICE_V5"]
    elif "v6" in tpu_accel or "v6" in tpu_type:
        tpu_metrics = ["TPU_V6E_PODSLICE"]
    else:
        tpu_metrics = ["TPU_LITE_PODSLICE_V5", "TPU_LITE_DEVICE_V5"]

# 2. Determine GPU quota metrics
gpu_accel_lower = gpu_accel.lower()
if gpu_quota_override:
    gpu_metrics = [gpu_quota_override]
elif use_spot:
    if "l4" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_L4_GPUS"]
    elif "a100-80gb" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_A100_80GB_GPUS"]
    elif "a100" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_A100_GPUS"]
    elif "t4" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_T4_GPUS"]
    elif "v100" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_V100_GPUS"]
    elif "p100" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_P100_GPUS"]
    elif "p4" in gpu_accel_lower:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_P4_GPUS"]
    else:
        gpu_metrics = ["PREEMPTIBLE_NVIDIA_L4_GPUS"]
else:
    if "l4" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_L4_GPUS"]
    elif "a100-80gb" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_A100_80GB_GPUS"]
    elif "a100" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_A100_GPUS"]
    elif "t4" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_T4_GPUS"]
    elif "v100" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_V100_GPUS"]
    elif "p100" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_P100_GPUS"]
    elif "p4" in gpu_accel_lower:
        gpu_metrics = ["NVIDIA_P4_GPUS"]
    else:
        gpu_metrics = ["NVIDIA_L4_GPUS"]

cmd = ["gcloud", "compute", "regions", "list", "--format=json(name,quotas)"]
if project_id:
    cmd.extend(["--project", project_id])

try:
    res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    regions_json = json.loads(res)
except Exception as e:
    sys.exit(1)

region_quota_map = {}
for r in regions_json:
    q_map = {q["metric"]: q for q in r.get("quotas", [])}
    tpu_avail = 0.0
    for tm in tpu_metrics:
        if tm in q_map:
            avail = float(q_map[tm].get("limit", 0.0)) - float(q_map[tm].get("usage", 0.0))
            if avail > tpu_avail:
                tpu_avail = avail
    gpu_avail = 0.0
    for gm in gpu_metrics:
        if gm in q_map:
            avail = float(q_map[gm].get("limit", 0.0)) - float(q_map[gm].get("usage", 0.0))
            if avail > gpu_avail:
                gpu_avail = avail
    region_quota_map[r["name"]] = {"tpu": tpu_avail, "gpu": gpu_avail}

print(json.dumps({
    "tpu_metrics": tpu_metrics,
    "gpu_metrics": gpu_metrics,
    "regions": region_quota_map
}))
EOF
  )

  if [[ -n "$QUOTA_OUTPUT" ]]; then
    TPU_METRICS_STR=$(echo "$QUOTA_OUTPUT" | jq -r '.tpu_metrics | join(", ")')
    GPU_METRICS_STR=$(echo "$QUOTA_OUTPUT" | jq -r '.gpu_metrics | join(", ")')
    echo "  Checked TPU quota metrics: $TPU_METRICS_STR"
    echo "  Checked GPU quota metrics: $GPU_METRICS_STR"

    FILTERED_TPU_ZONES=()
    for z in "${RAW_TPU_ZONES[@]}"; do
      r="${z%-*}"
      avail=$(echo "$QUOTA_OUTPUT" | jq -r ".regions[\"$r\"].tpu // 0")
      if (( $(echo "$avail > 0" | bc -l) )); then
        FILTERED_TPU_ZONES+=("$z")
      else
        echo "  [EXCLUDED] TPU zone $z in region $r (quota: $avail)"
      fi
    done

    FILTERED_GPU_ZONES=()
    for z in "${RAW_GPU_ZONES[@]}"; do
      r="${z%-*}"
      avail=$(echo "$QUOTA_OUTPUT" | jq -r ".regions[\"$r\"].gpu // 0")
      if (( $(echo "$avail > 0" | bc -l) )); then
        FILTERED_GPU_ZONES+=("$z")
      else
        echo "  [EXCLUDED] GPU zone $z in region $r (quota: $avail)"
      fi
    done

    TPU_ZONES=("${FILTERED_TPU_ZONES[@]}")
    GPU_ZONES=("${FILTERED_GPU_ZONES[@]}")
  else
    echo "Warning: Unable to fetch quota information. Proceeding with unfiltered catalog zones."
  fi
fi

if [[ ${#TPU_ZONES[@]} -eq 0 ]]; then
  echo "Error: No zones with available TPU quota found."
  exit 1
fi

if [[ ${#GPU_ZONES[@]} -eq 0 ]]; then
  echo "Error: No zones with available GPU quota found."
  exit 1
fi

# Find single zones offering both accelerators and with quota
COMMON_ZONES=()
for z in "${TPU_ZONES[@]}"; do
  for gz in "${GPU_ZONES[@]}"; do
    if [[ "$z" == "$gz" ]]; then
      COMMON_ZONES+=("$z")
      break
    fi
  done
done

# Map regions to TPU and GPU zones
declare -A TPU_REGION_MAP
declare -A GPU_REGION_MAP

for z in "${TPU_ZONES[@]}"; do
  r="${z%-*}"
  TPU_REGION_MAP["$r"]+="$z "
done

for z in "${GPU_ZONES[@]}"; do
  r="${z%-*}"
  GPU_REGION_MAP["$r"]+="$z "
done

# Find regions offering both accelerators
COMMON_REGIONS=()
for r in "${!TPU_REGION_MAP[@]}"; do
  if [[ -n "${GPU_REGION_MAP[$r]}" ]]; then
    COMMON_REGIONS+=("$r")
  fi
done

echo ""
echo "Found ${#COMMON_ZONES[@]} single zone(s) with valid catalog & quota for both accelerators:"
for z in "${COMMON_ZONES[@]}"; do
  echo "  - $z"
done

echo ""
echo "Found ${#COMMON_REGIONS[@]} region(s) with valid catalog & quota for both accelerators:"
for r in "${COMMON_REGIONS[@]}"; do
  echo "  - $r (TPU zones: ${TPU_REGION_MAP[$r]%% }; GPU zones: ${GPU_REGION_MAP[$r]%% })"
done
echo "=================================================="

# State Tracking & Caching
declare -A TPU_STATUS
declare -A GPU_STATUS

# Function to test TPU creation
check_tpu() {
  local zone="$1"
  local name="check-tpu-$zone"
  local spot_flag=()
  if [[ "$USE_SPOT" == "true" ]]; then
    spot_flag=(--spot)
  fi

  if gcloud compute tpus tpu-vm create "$name" \
    "${PROJECT_FLAG[@]}" \
    --zone="$zone" \
    --accelerator-type="$TPU_TYPE" \
    --version="$TPU_VERSION" \
    "${spot_flag[@]}" 2>&1 | grep -q "Created"; then
      TPU_STATUS["$zone"]="OK"
      return 0
  else
      TPU_STATUS["$zone"]="FAIL"
      return 1
  fi
}

delete_tpu() {
  local zone="$1"
  local name="check-tpu-$zone"
  gcloud compute tpus tpu-vm delete "$name" "${PROJECT_FLAG[@]}" --zone="$zone" --quiet &>/dev/null
}

# Function to test GPU creation
check_gpu() {
  local zone="$1"
  local name="check-gpu-$zone"
  local model_flag=()
  if [[ "$USE_SPOT" == "true" ]]; then
    model_flag=(--provisioning-model=SPOT)
  fi

  if gcloud compute instances create "$name" \
    "${PROJECT_FLAG[@]}" \
    --zone="$zone" \
    --machine-type="$GPU_MACHINE_TYPE" \
    "${model_flag[@]}" \
    --quiet 2>&1 | grep -q "Created"; then
      GPU_STATUS["$zone"]="OK"
      return 0
  else
      GPU_STATUS["$zone"]="FAIL"
      return 1
  fi
}

delete_gpu() {
  local zone="$1"
  local name="check-gpu-$zone"
  gcloud compute instances delete "$name" "${PROJECT_FLAG[@]}" --zone="$zone" --quiet &>/dev/null
}

# Cleanup on interrupt
cleanup() {
  echo -e "\nCleaning up any test instances..."
  for z in "${TPU_ZONES[@]}"; do
    delete_tpu "$z"
  done
  for z in "${GPU_ZONES[@]}"; do
    delete_gpu "$z"
  done
  exit 1
}
trap cleanup INT TERM

echo ""
echo "--- Phase 1: Checking Single Zones for Live Capacity ---"
FOUND_SINGLE_ZONE=""

for ZONE in "${COMMON_ZONES[@]}"; do
  echo "Testing single zone $ZONE..."
  
  echo "  -> Requesting TPU ($TPU_TYPE) in $ZONE..."
  if check_tpu "$ZONE"; then
    echo "  [OK] TPU capacity available in $ZONE."
    
    echo "  -> Requesting GPU ($GPU_MACHINE_TYPE) in $ZONE..."
    if check_gpu "$ZONE"; then
      echo "  [OK] GPU capacity available in $ZONE."
      echo ""
      echo "=================================================="
      echo "SUCCESS: Found single zone with BOTH TPU and GPU capacity!"
      echo "Zone:             $ZONE"
      echo "TPU Accelerator:  $TPU_ACCELERATOR_NAME ($TPU_TYPE)"
      echo "GPU Machine Type: $GPU_ACCELERATOR_NAME ($GPU_MACHINE_TYPE)"
      echo "=================================================="
      
      delete_gpu "$ZONE"
      delete_tpu "$ZONE"
      FOUND_SINGLE_ZONE="$ZONE"
      exit 0
    else
      echo "  [FAIL] GPU capacity not available in $ZONE."
      delete_tpu "$ZONE"
    fi
  else
    echo "  [FAIL] TPU capacity not available in $ZONE."
  fi
done

echo ""
echo "No single zone had simultaneous capacity."
echo "--- Phase 2: Checking Regions for Live Capacity Across Zones ---"

FOUND_REGION=""
for REGION in "${COMMON_REGIONS[@]}"; do
  echo "Testing region $REGION..."
  read -ra R_TPU_ZONES <<< "${TPU_REGION_MAP[$REGION]}"
  read -ra R_GPU_ZONES <<< "${GPU_REGION_MAP[$REGION]}"
  
  # Check if any candidate GPU zone in this region hasn't failed yet
  has_viable_gpu=false
  for GZ in "${R_GPU_ZONES[@]}"; do
    if [[ "${GPU_STATUS[$GZ]:-}" != "FAIL" ]]; then
      has_viable_gpu=true
      break
    fi
  done

  if [[ "$has_viable_gpu" != "true" ]]; then
    echo "  [SKIP] All GPU zones in region $REGION previously failed."
    continue
  fi

  for TZ in "${R_TPU_ZONES[@]}"; do
    if [[ "${TPU_STATUS[$TZ]:-}" == "FAIL" ]]; then
      echo "  -> Skipping TPU in $TZ (known failure from previous test)."
      continue
    fi

    # Check if there is any viable candidate GPU zone other than TZ (since TZ==GZ was already evaluated in Phase 1)
    has_candidate_gpu=false
    for GZ in "${R_GPU_ZONES[@]}"; do
      if [[ "$GZ" != "$TZ" && "${GPU_STATUS[$GZ]:-}" != "FAIL" ]]; then
        has_candidate_gpu=true
        break
      fi
    done

    if [[ "$has_candidate_gpu" != "true" ]]; then
      echo "  -> Skipping TPU in $TZ (no remaining candidate GPU zones in $REGION)."
      continue
    fi

    echo "  -> Requesting TPU ($TPU_TYPE) in $TZ..."
    if check_tpu "$TZ"; then
      echo "  [OK] TPU capacity found in $TZ."
      
      for GZ in "${R_GPU_ZONES[@]}"; do
        if [[ "$GZ" == "$TZ" ]]; then
          continue
        fi

        if [[ "${GPU_STATUS[$GZ]:-}" == "FAIL" ]]; then
          echo "    -> Skipping GPU in $GZ (known failure from previous test)."
          continue
        fi

        echo "    -> Requesting GPU ($GPU_MACHINE_TYPE) in $GZ..."
        if check_gpu "$GZ"; then
          echo "    [OK] GPU capacity found in $GZ."
          echo ""
          echo "=================================================="
          echo "SUCCESS: Found region with BOTH TPU and GPU capacity!"
          echo "Recommended Region: $REGION"
          echo "TPU Zone:          $TZ ($TPU_ACCELERATOR_NAME / $TPU_TYPE)"
          echo "GPU Zone:          $GZ ($GPU_ACCELERATOR_NAME / $GPU_MACHINE_TYPE)"
          echo "=================================================="
          
          delete_gpu "$GZ"
          delete_tpu "$TZ"
          FOUND_REGION="$REGION"
          exit 0
        else
          echo "    [FAIL] GPU capacity not available in $GZ."
        fi
      done
      
      delete_tpu "$TZ"
    else
      echo "  [FAIL] TPU capacity not available in $TZ."
    fi
  done
done

echo ""
echo "=================================================="
echo "FAIL: No live Spot capacity found in any candidate zone or region."
echo "=================================================="
exit 1
