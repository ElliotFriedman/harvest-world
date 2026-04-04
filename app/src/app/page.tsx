"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  IDKitWidget,
  ISuccessResult,
  VerificationLevel,
} from "@worldcoin/idkit";
import { MiniKit } from "@worldcoin/minikit-js";
import { encodeFunctionData, decodeAbiParameters } from "viem";
import {
  getBalances,
  getVaultTvl,
  getAgentStatus,
  triggerHarvest,
} from "../lib/client";

// ─── Constants ───────────────────────────────────────────────────────────────

const APP_ID = process.env.NEXT_PUBLIC_APP_ID as `app_${string}`;
const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;
const USDC_ADDRESS = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1" as const;
const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3" as const;
const WORLD_CHAIN_ID = 480;

// Minimal ABIs for on-chain calls
const VERIFY_HUMAN_ABI = [
  {
    name: "verifyHuman",
    type: "function" as const,
    inputs: [
      { name: "root", type: "uint256" },
      { name: "nullifierHash", type: "uint256" },
      { name: "proof", type: "uint256[8]" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const DEPOSIT_ABI = [
  {
    name: "deposit",
    type: "function" as const,
    inputs: [{ name: "_amount", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const PERMIT2_APPROVE_ABI = [
  {
    name: "approve",
    type: "function" as const,
    inputs: [
      { name: "token", type: "address" },
      { name: "spender", type: "address" },
      { name: "amount", type: "uint160" },
      { name: "expiration", type: "uint48" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const WITHDRAW_ABI = [
  {
    name: "withdraw",
    type: "function" as const,
    inputs: [{ name: "_shares", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

// ─── Helpers ─────────────────────────────────────────────────────────────────

// IDKit v3 returns proof as ABI-encoded uint256[8] (with 32-byte offset prefix)
function decodeProof(proof: `0x${string}`): bigint[] {
  return [...decodeAbiParameters([{ type: "uint256[8]" }], proof)[0]];
}

function formatUSDC(amount: number): string {
  return amount.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/** Format a bigint with 6 decimals (USDC) to a human-readable string */
function formatBigintUSDC(raw: bigint): string {
  const whole = raw / BigInt(1e6);
  const frac = raw % BigInt(1e6);
  const fracStr = frac.toString().padStart(6, "0").slice(0, 2);
  return `${whole.toLocaleString()}.${fracStr}`;
}

// ─── Component ────────────────────────────────────────────────────────────────

export default function Terminal() {
  const [lines, setLines] = useState<string[]>([
    "HARVEST v1.3 — Agentic DeFi, for humans.",
    "World Chain yield aggregator.",
    "",
  ]);
  const [input, setInput] = useState("");
  const [pendingDeposit, setPendingDeposit] = useState<number | null>(null);
  const [idkitOpen, setIdkitOpen] = useState(false);
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [isVerified, setIsVerified] = useState(false);
  const [hasShares, setHasShares] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Scroll to bottom whenever lines change
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  // Check for cached wallet address on mount (no auto-auth)
  useEffect(() => {
    if (!MiniKit.isInstalled()) return;
    if (MiniKit.user?.walletAddress) {
      setWalletAddress(MiniKit.user.walletAddress);
    }
  }, []);

  const print = useCallback((...newLines: string[]) => {
    setLines((prev) => [...prev, ...newLines]);
  }, []);

  // ── Command handlers ────────────────────────────────────────────────────────

  async function handleHelp() {
    print(
      "Commands:",
      "  vaults         — list vaults + APY",
      "  deposit <n>    — deposit USDC",
      "  withdraw all   — exit position",
      "  portfolio      — your balance",
      "  agent status   — harvester info",
      "  agent harvest  — trigger harvest",
      "  clear          — clear screen",
      ""
    );
  }

  async function handleVaults() {
    print("Loading vault data...");
    try {
      const tvl = await getVaultTvl();
      const tvlFormatted = formatBigintUSDC(tvl);
      print(
        "USDC (Re7 Morpho)",
        "  APY:    4.23%",
        `  TVL:    $${tvlFormatted}`,
        "  Status: LIVE",
        "",
        "deposit <amount> to enter",
        ""
      );
    } catch {
      print(
        "USDC (Re7 Morpho)",
        "  APY:    4.23%",
        "  TVL:    --",
        "  Status: LIVE",
        "",
        "deposit <amount> to enter",
        ""
      );
    }
  }

  async function handleDeposit(args: string[]) {
    const amount = parseFloat(args[0]);
    if (isNaN(amount) || amount <= 0) {
      print("Usage: deposit <amount>  (e.g. deposit 50)", "");
      return;
    }

    if (!MiniKit.isInstalled()) {
      print("Error: Open this app inside World App.", "");
      return;
    }

    if (!walletAddress) {
      print("Connect your wallet first. Tap 'get started' below.", "");
      return;
    }

    if (!isVerified) {
      print(
        `Deposit ${formatUSDC(amount)} USDC requested.`,
        "World ID verification required first — opening IDKit...",
        ""
      );
      setPendingDeposit(amount);
      await openIdkit();
      return;
    }

    await executeDeposit(amount);
  }

  async function handleWithdraw(args: string[]) {
    if (!MiniKit.isInstalled()) {
      print("Error: Open this app inside World App to withdraw.", "");
      return;
    }

    if (!walletAddress) {
      print("Error: Wallet not connected.", "");
      return;
    }

    if (!isVerified) {
      print("Error: World ID verification required before withdrawing.", "");
      return;
    }

    if (!args[0]) {
      print("Usage: withdraw all  or  withdraw <amount>", "");
      return;
    }

    print("Reading vault position...");

    try {
      const { vaultShares, pricePerShare } = await getBalances(walletAddress);

      if (vaultShares === BigInt(0)) {
        print("You have no vault shares to withdraw.", "");
        return;
      }

      let sharesToWithdraw: bigint;

      if (args[0] === "all") {
        sharesToWithdraw = vaultShares;
        const usdValue = (vaultShares * pricePerShare) / BigInt(1e18);
        print(`Withdrawing all shares (~$${formatBigintUSDC(usdValue)} USDC)...`);
      } else {
        const amount = parseFloat(args[0]);
        if (isNaN(amount) || amount <= 0) {
          print("Usage: withdraw all  or  withdraw <amount>", "");
          return;
        }

        // Convert USDC amount to shares: shares = (amountRaw * 1e18) / pricePerShare
        const amountRaw = BigInt(Math.floor(amount * 1e6));
        if (pricePerShare === BigInt(0)) {
          print("Error: Could not read price per share.", "");
          return;
        }
        sharesToWithdraw = (amountRaw * BigInt(1e18)) / pricePerShare;

        if (sharesToWithdraw > vaultShares) {
          const maxUsd = (vaultShares * pricePerShare) / BigInt(1e18);
          print(
            `Error: Requested ${formatUSDC(amount)} USDC but you only have ~$${formatBigintUSDC(maxUsd)}.`,
            "Use 'withdraw all' to withdraw everything.",
            ""
          );
          return;
        }

        print(`Withdrawing ~${formatUSDC(amount)} USDC (${sharesToWithdraw} shares)...`);
      }

      await executeWithdraw(sharesToWithdraw);
    } catch (err) {
      print(
        `Error: ${err instanceof Error ? err.message : "unknown"}`,
        ""
      );
    }
  }

  async function handlePortfolio() {
    if (!walletAddress) {
      print("Connect via World App to view your portfolio.", "");
      return;
    }

    print(`Loading portfolio for ${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}...`);

    try {
      const { usdcBalance, vaultShares, pricePerShare } = await getBalances(walletAddress);

      // Update hasShares state for button context
      if (vaultShares > BigInt(0)) setHasShares(true);

      // Calculate USD value of vault shares
      const usdValue = (vaultShares * pricePerShare) / BigInt(1e18);

      print(
        `Portfolio for ${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`,
        `  USDC in wallet: $${formatBigintUSDC(usdcBalance)}`,
        `  Vault shares:   ${formatBigintUSDC(vaultShares)} mooUSDC`,
        `  USD value:      $${formatBigintUSDC(usdValue)}`,
        `  Verified:       ${isVerified ? "yes" : "no"}`,
        ""
      );
    } catch {
      print(
        `Portfolio for ${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`,
        "  Error loading on-chain data. Try again.",
        ""
      );
    }
  }

  async function handleAgentStatus() {
    print("Loading agent status...");
    try {
      const data = await getAgentStatus();

      // Format time-ago for last harvest
      let lastHarvestStr = "never";
      if (data.lastHarvest) {
        const ago = Date.now() - new Date(data.lastHarvest.timestamp).getTime();
        const mins = Math.floor(ago / 60_000);
        if (mins < 60) lastHarvestStr = `${mins}m ago`;
        else {
          const hrs = Math.floor(mins / 60);
          lastHarvestStr = `${hrs}h ${mins % 60}m ago`;
        }
      }

      // Format next check
      const nextMs = new Date(data.nextCheck).getTime() - Date.now();
      const nextHrs = Math.max(0, Math.floor(nextMs / 3600_000));
      const nextMins = Math.max(0, Math.floor((nextMs % 3600_000) / 60_000));
      const nextStr = nextHrs > 0 ? `in ~${nextHrs}h ${nextMins}m` : `in ~${nextMins}m`;

      // Pending rewards line
      const pendingStr = data.pendingRewards
        ? `${data.pendingRewards.amount} (~$${data.pendingRewards.usdValue.toFixed(2)})`
        : "0 WLD";

      print(
        "HARVESTER AGENT",
        `  Status:         \u25CF ACTIVE`,
        "  Strategy:       StrategyMorpho (Re7 USDC)",
        `  Last harvest:   ${lastHarvestStr}`,
        `  Next check:     ${nextStr}`,
        `  Pending yield:  ${pendingStr}`,
        ""
      );

      // Recent harvests table
      if (data.harvests.length > 0) {
        print(
          "  RECENT HARVESTS",
          "  +------------------+-------------+-------------+-----------+",
          "  | Time             | Claimed     | Compound    | Tx        |",
          "  +------------------+-------------+-------------+-----------+"
        );

        for (const h of data.harvests.slice(0, 5)) {
          const t = new Date(h.timestamp);
          const timeStr = `${(t.getMonth() + 1).toString().padStart(2, "0")}/${t.getDate().toString().padStart(2, "0")} ${t.getHours().toString().padStart(2, "0")}:${t.getMinutes().toString().padStart(2, "0")}`;
          const claimed = h.rewardsClaimed.padEnd(11).slice(0, 11);
          const compound = h.wantEarned.padEnd(11).slice(0, 11);
          const tx = h.txHash.slice(0, 8) + "..";
          print(`  | ${timeStr.padEnd(16)} | ${claimed} | ${compound} | ${tx} |`);
        }

        print(
          "  +------------------+-------------+-------------+-----------+",
          ""
        );
      }
    } catch {
      print(
        "HARVESTER AGENT",
        "  Status:         \u25CF ACTIVE",
        "  Error loading live data. Using defaults.",
        "  Strategy:       StrategyMorpho (Re7 USDC)",
        "  Next check:     in ~6h",
        ""
      );
    }
  }

  async function handleAgentHarvest() {
    print("HARVESTING...");
    print("  [1/3] Checking Merkl rewards...");

    try {
      const result = await triggerHarvest();

      if (!result.success) {
        if (result.reason === "no_rewards") {
          print("        No unclaimed rewards found.", "");
        } else if (result.reason === "missing_key") {
          print("        Agent wallet not configured.", "");
        } else {
          print(`        Error: ${result.message ?? "harvest failed"}`, "");
        }
        return;
      }

      print(`        ${result.rewardsClaimed ?? "rewards"} available`);
      print(`  [2/3] Claiming + swapping...        TX: ${(result.txHash ?? "").slice(0, 10)}...`);
      print(`  [3/3] Compounded into vault         +${result.wantEarned ?? "-- USDC"}`);

      // Share price change
      if (result.oldSharePrice && result.newSharePrice) {
        const fmtPrice = (raw: string) => {
          const bi = BigInt(raw);
          const whole = bi / BigInt(1e18);
          const frac = (bi % BigInt(1e18)).toString().padStart(18, "0").slice(0, 6);
          return `${whole}.${frac}`;
        };
        print("");
        print(`  Share price: ${fmtPrice(result.oldSharePrice)} -> ${fmtPrice(result.newSharePrice)}`);
      }

      print("  Next harvest in ~6h.", "");
    } catch {
      print("        Error: Could not reach harvest endpoint.", "");
    }
  }

  // ── IDKit flow ───────────────────────────────────────────────────────────────

  async function openIdkit() {
    if (!walletAddress) {
      print("Error: Wallet must be connected before verification.", "");
      setPendingDeposit(null);
      return;
    }
    setIdkitOpen(true);
  }

  async function handleVerify(result: ISuccessResult): Promise<void> {
    const res = await fetch("/api/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...result,
        action: "verify-human",
        signal: walletAddress,
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.detail ?? "Verification failed");
    }
  }

  const handleIdkitSuccess = useCallback(
    async (result: ISuccessResult) => {
      setIdkitOpen(false);
      print("World ID verified. Registering on-chain...");

      if (!MiniKit.isInstalled() || !walletAddress) {
        print("Error: MiniKit not available.", "");
        return;
      }

      try {
        const root = BigInt(result.merkle_root);
        const nullifierHash = BigInt(result.nullifier_hash);
        const proofArray = decodeProof(result.proof as `0x${string}`) as [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint];

        const verifyCalldata = encodeFunctionData({
          abi: VERIFY_HUMAN_ABI,
          functionName: "verifyHuman",
          args: [root, nullifierHash, proofArray],
        });

        const { data } = await MiniKit.sendTransaction({
          chainId: WORLD_CHAIN_ID,
          transactions: [
            {
              to: VAULT_ADDRESS,
              data: verifyCalldata,
            },
          ],
        });

        if (data.status !== "success") {
          print(`Error: tx failed — status=${data.status}`, "");
          return;
        }

        setIsVerified(true);
        print(
          `Verified. UserOp: ${data.userOpHash.slice(0, 10)}...`,
          ""
        );

        // Auto-fetch balance after verification
        const addr = walletAddress;
        if (addr) {
          try {
            const { usdcBalance, vaultShares } = await getBalances(addr);
            if (vaultShares > BigInt(0)) setHasShares(true);
            if (usdcBalance === BigInt(0)) {
              print("Top up your wallet with USDC to deposit.", "");
            } else {
              print(`USDC balance: $${formatBigintUSDC(usdcBalance)}`, "");
              print("Type 'deposit <amount>' or tap below.", "");
            }
          } catch {
            /* ignore balance fetch errors */
          }
        }

        // If a deposit was waiting, execute it now
        if (pendingDeposit !== null) {
          const amount = pendingDeposit;
          setPendingDeposit(null);
          await executeDeposit(amount);
        }
      } catch (err) {
        print(
          `Error registering on-chain: ${err instanceof Error ? err.message : "unknown"}`,
          ""
        );
      }
    },
    [pendingDeposit, print, walletAddress]
  );

  // ── Transaction executors ──────────────────────────────────────────────────

  async function executeDeposit(amount: number) {
    print(`Depositing ${formatUSDC(amount)} USDC...`);

    if (!MiniKit.isInstalled()) {
      print("Error: MiniKit not available.", "");
      return;
    }

    try {
      // amount in USDC has 6 decimals
      const amountRaw = BigInt(Math.floor(amount * 1e6));

      // Encode Permit2 approve calldata
      const approveCalldata = encodeFunctionData({
        abi: PERMIT2_APPROVE_ABI,
        functionName: "approve",
        args: [
          USDC_ADDRESS,
          VAULT_ADDRESS,
          amountRaw, // uint160
          0,         // expiration=0 — single-use, consumed in same tx batch
        ],
      });

      // Encode vault deposit calldata
      const depositCalldata = encodeFunctionData({
        abi: DEPOSIT_ABI,
        functionName: "deposit",
        args: [amountRaw],
      });

      // Bundle: Permit2 approve + vault deposit in one sendTransaction
      const { data } = await MiniKit.sendTransaction({
        chainId: WORLD_CHAIN_ID,
        transactions: [
          {
            to: PERMIT2_ADDRESS,
            data: approveCalldata,
          },
          {
            to: VAULT_ADDRESS,
            data: depositCalldata,
          },
        ],
      });

      if (data.status !== "success") {
        print("Error: Deposit transaction failed.", "");
        return;
      }

      setHasShares(true);
      print(
        `Deposited ${formatUSDC(amount)} USDC.`,
        `  UserOp: ${data.userOpHash.slice(0, 10)}...`,
        "  Run 'portfolio' to see your position.",
        ""
      );
    } catch (err) {
      print(
        `Error: ${err instanceof Error ? err.message : "unknown"}`,
        ""
      );
    }
  }

  async function executeWithdraw(shares: bigint) {
    if (!MiniKit.isInstalled()) {
      print("Error: MiniKit not available.", "");
      return;
    }

    try {
      const withdrawCalldata = encodeFunctionData({
        abi: WITHDRAW_ABI,
        functionName: "withdraw",
        args: [shares],
      });

      const { data } = await MiniKit.sendTransaction({
        chainId: WORLD_CHAIN_ID,
        transactions: [
          {
            to: VAULT_ADDRESS,
            data: withdrawCalldata,
          },
        ],
      });

      if (data.status !== "success") {
        print("Error: Withdrawal transaction failed.", "");
        return;
      }

      print(
        "Withdrawal complete.",
        `  UserOp: ${data.userOpHash.slice(0, 10)}...`,
        "  Run 'portfolio' to see updated position.",
        ""
      );
    } catch (err) {
      print(
        `Error: ${err instanceof Error ? err.message : "unknown"}`,
        ""
      );
    }
  }

  // ── Get Started flow ────────────────────────────────────────────────────────

  async function handleGetStarted() {
    if (!MiniKit.isInstalled()) {
      print("Open this app inside World App.", "");
      return;
    }

    print("Connecting wallet...");

    // Step 1: walletAuth
    let addr = walletAddress;
    if (!addr) {
      try {
        const result = await MiniKit.walletAuth({
          nonce: crypto.randomUUID().replace(/-/g, ""),
          statement: "Sign in to Harvest",
        });
        if (!result?.data?.address) {
          print("Error: wallet connection failed.", "");
          return;
        }
        addr = result.data.address;
        setWalletAddress(addr);
        print(`Connected: ${addr.slice(0, 6)}...${addr.slice(-4)}`);
      } catch {
        print("Error: wallet connection failed.", "");
        return;
      }
    }

    // Step 2: immediately open IDKit for World ID verification
    print("Verifying humanity...");
    setIdkitOpen(true);
  }

  // ── Input handling ───────────────────────────────────────────────────────────

  async function handleCommand(raw: string) {
    const trimmed = raw.trim().toLowerCase();
    print(`harvest> ${raw}`);

    if (!trimmed) return;

    const [cmd, ...args] = trimmed.split(/\s+/);

    if (cmd === "help") {
      await handleHelp();
    } else if (cmd === "vaults") {
      await handleVaults();
    } else if (cmd === "deposit") {
      await handleDeposit(args);
    } else if (cmd === "withdraw") {
      await handleWithdraw(args);
    } else if (cmd === "portfolio") {
      await handlePortfolio();
    } else if (cmd === "agent" && args[0] === "status") {
      await handleAgentStatus();
    } else if (cmd === "agent" && args[0] === "harvest") {
      await handleAgentHarvest();
    } else if (cmd === "clear") {
      setLines([]);
    } else {
      print(`Unknown command: '${cmd}'. Type 'help' for options.`, "");
    }
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      const val = input;
      setInput("");
      handleCommand(val);
    }
  }

  // ── Contextual shortcut buttons ─────────────────────────────────────────────

  function getButtons(): { label: string; action: () => void }[] {
    if (!walletAddress || !isVerified) {
      return [{ label: "get started", action: handleGetStarted }];
    }
    // Verified — show contextual buttons
    if (hasShares) {
      return [
        { label: "deposit", action: () => handleCommand("deposit 50") },
        { label: "portfolio", action: () => handleCommand("portfolio") },
        { label: "withdraw all", action: () => handleCommand("withdraw all") },
      ];
    }
    return [
      { label: "deposit", action: () => handleCommand("deposit 50") },
      { label: "portfolio", action: () => handleCommand("portfolio") },
      { label: "agent status", action: () => handleCommand("agent status") },
      { label: "withdraw all", action: () => handleCommand("withdraw all") },
    ];
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  return (
    <div
      style={{
        height: "100vh",
        display: "flex",
        flexDirection: "column",
        padding: "10px",
        overflow: "hidden",
      }}
      onClick={() => inputRef.current?.focus()}
    >
      {/* Scrollable output */}
      <div
        style={{
          flex: 1,
          overflowY: "auto",
          wordBreak: "break-word",
          whiteSpace: "pre-wrap",
        }}
      >
        {lines.map((line, i) => (
          <div key={i}>{line || "\u00A0"}</div>
        ))}
        <div ref={bottomRef} />
      </div>

      {/* Shortcut buttons (mobile UX) — contextual based on user state */}
      <div
        style={{
          display: "flex",
          gap: "8px",
          paddingTop: "8px",
          flexWrap: "wrap",
        }}
      >
        {getButtons().map((btn) => (
          <button
            key={btn.label}
            onClick={btn.action}
            style={{
              background: "transparent",
              border: "1px solid #00ff41",
              color: "#00ff41",
              fontFamily: "inherit",
              fontSize: "11px",
              padding: "4px 8px",
              cursor: "pointer",
            }}
          >
            {btn.label}
          </button>
        ))}
      </div>

      {/* Input row */}
      <div style={{ display: "flex", alignItems: "center", paddingTop: "6px" }}>
        <span style={{ marginRight: "8px" }}>harvest&gt;</span>
        <input
          ref={inputRef}
          autoFocus
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKeyDown}
          style={{
            flex: 1,
            background: "transparent",
            border: "none",
            outline: "none",
            color: "#00ff41",
            fontFamily: "inherit",
            fontSize: "inherit",
            caretColor: "#00ff41",
          }}
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
        />
      </div>

      {/* IDKit v2 widget — render prop pattern */}
      {walletAddress && (
        <IDKitWidget
          app_id={APP_ID}
          action="verify-human"
          signal={walletAddress}
          verification_level={VerificationLevel.Orb}
          handleVerify={handleVerify}
          onSuccess={handleIdkitSuccess}
          onError={(error) => {
            print(`World ID error: ${JSON.stringify(error)}`, "");
            setIdkitOpen(false);
            setPendingDeposit(null);
          }}
        >
          {({ open }) => {
            if (idkitOpen) {
              setTimeout(open, 0);
            }
            return <></>;
          }}
        </IDKitWidget>
      )}
    </div>
  );
}
