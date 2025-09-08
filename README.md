# AzureDNS

# Private DNS A Record Sync Script

Synchronize all A record-sets (with TTL) from a source Azure Private DNS zone to a destination zone located (optionally) in a different subscription / resource group.

## What It Does
- Enumerates every A record-set in the source Private DNS zone.
- Recreates (or updates) the record-set in the destination zone with the same TTL.
- Removes all existing A records in the destination record-set before adding the source ones (ensures exact mirror).
- Leaves other record types (AAAA, CNAME, PTR, SRV, TXT, etc.) untouched.
- Stops on first error (strict mode: `set -euo pipefail`).

## What It Does NOT Do
- Does not copy non-A record types.
- Does not create the destination zone or resource group (they must already exist).
- Does not handle incremental diffs (always replaces destination A records per set).
- Does not paginate around extremely large zones (Azure CLI handles typical sizes).

## Prerequisites
- Azure CLI (tested with `az >= 2.50`).
- Logged in: `az login` (and if needed: `az account set --subscription <id>`).
- RBAC: Need `Private DNS Zone Contributor` (or higher) on both zones’ subscriptions.
- Bash shell.

## Configuration
Edit the variables at the top of the script before running:
