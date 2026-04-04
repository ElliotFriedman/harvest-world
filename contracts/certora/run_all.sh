#!/bin/bash
# =============================================================================
# run_all.sh — Submit all Certora verification jobs sequentially.
#
# Usage:
#   bash certora/run_all.sh
#
# Prerequisites:
#   - CERTORAKEY env variable set to your Certora API key
#   - certoraRun CLI installed: pip install certora-cli
#   - solc 0.8.28 on PATH: solc-select install 0.8.28 && solc-select use 0.8.28
#   - Foundry dependencies installed: forge install (run from contracts/)
#
# Each job is submitted to the Certora cloud.  The CLI prints a URL for the
# verification report after submission.  Jobs run in parallel on the Certora
# infrastructure; this script waits for each submission to be acknowledged
# before proceeding to the next.
#
# Exit codes:
#   0  — All jobs submitted successfully
#   1  — One or more submissions failed (set -e exits on first failure)
# =============================================================================

set -e

# Resolve the directory containing this script so we can run from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(dirname "$SCRIPT_DIR")"

# Verify CERTORAKEY is set before submitting any jobs.
if [ -z "$CERTORAKEY" ]; then
  echo "ERROR: CERTORAKEY environment variable is not set."
  echo "       Export your Certora API key: export CERTORAKEY=<your_key>"
  exit 1
fi

# Verify certoraRun is on PATH.
if ! command -v certoraRun &> /dev/null; then
  echo "ERROR: certoraRun is not on PATH."
  echo "       Install it with: pip install certora-cli"
  exit 1
fi

echo "============================================================"
echo " Harvest World — Certora Formal Verification"
echo " Submitting from: $CONTRACTS_DIR"
echo "============================================================"
echo ""

# Change to the contracts directory so relative paths in .conf files resolve.
cd "$CONTRACTS_DIR"

# ---------------------------------------------------------------------------
# 1. BeefyVaultV7
#    Covers: share arithmetic, access control, earn flow, price-per-share,
#            round-trip safety, depositor isolation.
# ---------------------------------------------------------------------------
echo "[1/3] Submitting BeefyVaultV7 verification..."
certoraRun certora/confs/BeefyVaultV7.conf
echo "      Submitted. See report URL above."
echo ""

# ---------------------------------------------------------------------------
# 2. BaseAllToNativeFactoryStrat
#    Covers: locked-profit decay, access control (vault-only + manager-only),
#            pause safety, harvest timestamp update.
# ---------------------------------------------------------------------------
echo "[2/3] Submitting BaseStrategy verification..."
certoraRun certora/confs/BaseStrategy.conf
echo "      Submitted. See report URL above."
echo ""

# ---------------------------------------------------------------------------
# 3. StrategyMorphoMerkl
#    Covers: Morpho pool accounting, deposit/withdraw atomicity, Merkl claim
#            isolation, reward token safety (cannot add want/native/morphoVault).
# ---------------------------------------------------------------------------
echo "[3/3] Submitting StrategyMorphoMerkl verification..."
certoraRun certora/confs/StrategyMorphoMerkl.conf
echo "      Submitted. See report URL above."
echo ""

echo "============================================================"
echo " All 3 verification jobs submitted successfully."
echo " Visit https://prover.certora.com to track job status."
echo "============================================================"
