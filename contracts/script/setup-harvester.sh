#!/usr/bin/env bash
set -euo pipefail

# ─── Harvest Agent Burner Wallet Setup ────────────────────────────────────────
# Generates a burner wallet, funds it with ETH, and transfers strategy ownership.
# Uses the solidity-labs-deployer keystore for signing.
# ──────────────────────────────────────────────────────────────────────────────

RPC_URL="https://worldchain.drpc.org"
STRATEGY="0x313bA1D5D5AA1382a80BA839066A61d33C110489"
KEYSTORE="solidity-labs-deployer"
GAS_AMOUNT="0.002ether"
SECRETS_FILE="$(dirname "$0")/../.harvester-wallet.json"

# ── Step 1: Generate burner wallet ────────────────────────────────────────────

echo "=== Step 1: Generating burner wallet ==="
WALLET_OUTPUT=$(cast wallet new)
BURNER_ADDRESS=$(echo "$WALLET_OUTPUT" | grep "Address:" | awk '{print $2}')
BURNER_KEY=$(echo "$WALLET_OUTPUT" | grep "Private key:" | awk '{print $3}')

echo "  Burner address:  $BURNER_ADDRESS"
echo "  Burner key:      $BURNER_KEY"

# Save to file BEFORE doing anything irreversible
cat > "$SECRETS_FILE" <<EOF
{
  "address": "$BURNER_ADDRESS",
  "privateKey": "$BURNER_KEY",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "strategy": "$STRATEGY",
  "chainId": 480
}
EOF
chmod 600 "$SECRETS_FILE"
echo "  Saved to: $SECRETS_FILE"
echo ""

# ── Step 2: Fund burner with ETH for gas ──────────────────────────────────────

echo "=== Step 2: Funding burner with $GAS_AMOUNT ==="
cast send "$BURNER_ADDRESS" \
  --value "$GAS_AMOUNT" \
  --rpc-url "$RPC_URL" \
  --account "$KEYSTORE"

BALANCE=$(cast balance "$BURNER_ADDRESS" --rpc-url "$RPC_URL" --ether)
echo "  Burner balance: $BALANCE ETH"
echo ""

# ── Step 3: Transfer strategy ownership to burner ─────────────────────────────

echo "=== Step 3: Transferring strategy ownership to burner ==="
CURRENT_OWNER=$(cast call "$STRATEGY" "owner()(address)" --rpc-url "$RPC_URL")
echo "  Current owner: $CURRENT_OWNER"

cast send "$STRATEGY" \
  "transferOwnership(address)" "$BURNER_ADDRESS" \
  --rpc-url "$RPC_URL" \
  --account "$KEYSTORE"

NEW_OWNER=$(cast call "$STRATEGY" "owner()(address)" --rpc-url "$RPC_URL")
echo "  New owner:     $NEW_OWNER"
echo ""

# ── Step 4: Verify ────────────────────────────────────────────────────────────

echo "=== Verification ==="
if [ "$(echo "$NEW_OWNER" | tr '[:upper:]' '[:lower:]')" = "$(echo "$BURNER_ADDRESS" | tr '[:upper:]' '[:lower:]')" ]; then
  echo "  Ownership transfer: OK"
else
  echo "  ERROR: Ownership transfer failed!"
  echo "  Expected: $BURNER_ADDRESS"
  echo "  Got:      $NEW_OWNER"
  exit 1
fi

echo ""
echo "=== Done ==="
echo ""
echo "Set these in Vercel:"
echo "  AGENT_PRIVATE_KEY=$BURNER_KEY"
echo ""
echo "Register with AgentKit:"
echo "  npx @worldcoin/agentkit-cli register $BURNER_ADDRESS"
