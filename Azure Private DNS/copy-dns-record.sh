# -----------------------------
# Configuration
# -----------------------------
SOURCE_SUBSCRIPTION_ID="source-subscription-id"   # subscription GUID (not a resource group)
TARGET_SUBSCRIPTION_ID="target-subscription-id"   # subscription GUID (not a resource group)
SOURCE_RG="SourceResourceGroup"                   # source resource group name
SOURCE_ZONE="SourcePrivateDNSZone"                # source Private DNS zone name
DEST_RG="DestinationResourceGroup"                # destination resource group name
DEST_ZONE="DestinationPrivateDNSZone"             # destination Private DNS zone name

# Copy only A records from source Private DNS zone to destination
set -euo pipefail

# Switch subscription helper (does not change resource groups)
ensure_subscription() {
  local sub="$1"
  local cur
  cur="$(az account show --query id -o tsv 2>/dev/null || true)"
  if [ -z "$cur" ] || [ "$cur" != "$sub" ]; then
    echo "Switching to subscription: $sub"
    az account set --subscription "$sub"
  fi
  local active
  active="$(az account show --query id -o tsv)"
  if [ "$active" != "$sub" ]; then
    echo "Error: Active subscription is $active, expected $sub" >&2
    exit 1
  fi
}

# Validate zones exist
ensure_subscription "$SOURCE_SUBSCRIPTION_ID"
if ! az network private-dns zone show -g "$SOURCE_RG" -n "$SOURCE_ZONE" >/dev/null 2>&1; then
  echo "Error: Source zone '$SOURCE_ZONE' not found in RG '$SOURCE_RG'." >&2
  exit 1
fi
ensure_subscription "$TARGET_SUBSCRIPTION_ID"
if ! az network private-dns zone show -g "$DEST_RG" -n "$DEST_ZONE" >/dev/null 2>&1; then
  echo "Error: Destination zone '$DEST_ZONE' not found in RG '$DEST_RG'." >&2
  exit 1
fi

# Enumerate A record-set names from source
ensure_subscription "$SOURCE_SUBSCRIPTION_ID"
mapfile -t A_NAMES < <(az network private-dns record-set a list -g "$SOURCE_RG" -z "$SOURCE_ZONE" --query "[].name" -o tsv)

for NAME in "${A_NAMES[@]:-}"; do
  # Get TTL and A records in source
  TTL="$(az network private-dns record-set a show -g "$SOURCE_RG" -z "$SOURCE_ZONE" -n "$NAME" --query ttl -o tsv || echo 3600)"
  mapfile -t SRC_IPS < <(az network private-dns record-set a show -g "$SOURCE_RG" -z "$SOURCE_ZONE" -n "$NAME" --query "aRecords[].ipv4Address" -o tsv || true)

  # Prepare destination record-set (create/update TTL)
  ensure_subscription "$TARGET_SUBSCRIPTION_ID"
  if ! az network private-dns record-set a show -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" >/dev/null 2>&1; then
    az network private-dns record-set a create -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" --ttl "${TTL:-3600}" >/dev/null
  else
    az network private-dns record-set a update -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" --set ttl="${TTL:-3600}" >/dev/null
    # Clear existing A records to ensure exact sync
    mapfile -t DEST_IPS < <(az network private-dns record-set a show -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" --query "aRecords[].ipv4Address" -o tsv || true)
    for DIP in "${DEST_IPS[@]:-}"; do
      [ -n "${DIP:-}" ] && az network private-dns record-set a remove-record -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" --ipv4-address "$DIP" >/dev/null || true
    done
  fi

  # Add source A records into destination
  for IP in "${SRC_IPS[@]:-}"; do
    [ -n "${IP:-}" ] && az network private-dns record-set a add-record -g "$DEST_RG" -z "$DEST_ZONE" -n "$NAME" --ipv4-address "$IP" >/dev/null || true
  done

  COUNT=${#SRC_IPS[@]}
  echo "Synced A record-set: $NAME (TTL=${TTL:-3600}, count=$COUNT)"
done

echo "Done syncing A records from $SOURCE_RG/$SOURCE_ZONE to $DEST_RG/$DEST_ZONE."
