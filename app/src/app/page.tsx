"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  IDKitRequestWidget,
  IDKitResult,
  IDKitErrorCodes,
  RpContext,
  ResponseItemV3,
  ResponseItemV4,
  orbLegacy,
} from "@worldcoin/idkit";
import { MiniKit } from "@worldcoin/minikit-js";
import { encodeFunctionData } from "viem";
import { getBalances, getVaultTvl } from "../lib/client";

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

// IDKit v3 returns proof as 0x + 8 packed uint256s (64 hex chars each = 512 hex chars)
function decodeProof(hex: string): bigint[] {
  const raw = hex.startsWith("0x") ? hex.slice(2) : hex;
  return Array.from({ length: 8 }, (_, i) =>
    BigInt("0x" + raw.slice(i * 64, (i + 1) * 64))
  );
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
    "HARVEST v1.1 — Agentic DeFi, for humans.",
    "World Chain yield aggregator.",
    "",
  ]);
  const [input, setInput] = useState("");
  const [pendingDeposit, setPendingDeposit] = useState<number | null>(null);
  const [idkitOpen, setIdkitOpen] = useState(false);
  const [rpContext, setRpContext] = useState<RpContext | null>(null);
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [isVerified, setIsVerified] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Scroll to bottom whenever lines change
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  // Connect wallet via MiniKit on mount
  useEffect(() => {
    async function connect() {
      if (!MiniKit.isInstalled()) return;

      // If already authed, use cached address
      if (MiniKit.user?.walletAddress) {
        setWalletAddress(MiniKit.user.walletAddress);
        return;
      }

      try {
        const result = await MiniKit.walletAuth({
          nonce: crypto.randomUUID().replace(/-/g, ""),
          statement: "Sign in to Harvest",
        });
        if (result?.data?.address) {
          setWalletAddress(result.data.address);
        }
      } catch {
        // User rejected or MiniKit not ready — silently continue
      }
    }
    connect();
  }, []);

  const print = useCallback((...newLines: string[]) => {
    setLines((prev) => [...prev, ...newLines]);
  }, []);

  // ── Command handlers ────────────────────────────────────────────────────────

  async function handleHelp() {
    print(
      "Commands:",
      "  vaults       — list vaults + APY",
      "  deposit <n>  — deposit USDC",
      "  withdraw all — exit position",
      "  portfolio    — your balance",
      "  agent status — harvester info",
      "  clear        — clear screen",
      ""
    );
  }

  async function handleVaults() {
    print("Loading vault data...");
    try {
      const tvl = await getVaultTvl();
      const tvlFormatted = formatBigintUSDC(tvl);
      print(
        "┌─────────────────────────────────────────────────────┐",
        "│  Vault          APY     TVL              Status     │",
        "├─────────────────────────────────────────────────────┤",
        `│  USDC (Re7)     4.23%   $${tvlFormatted.padEnd(15)} ● LIVE     │`,
        "└─────────────────────────────────────────────────────┘",
        "Deposit: harvest> deposit <amount>",
        ""
      );
    } catch {
      print(
        "┌─────────────────────────────────────────────────────┐",
        "│  Vault          APY     TVL         Status          │",
        "├─────────────────────────────────────────────────────┤",
        "│  USDC (Re7)     4.23%   --          ● LIVE          │",
        "└─────────────────────────────────────────────────────┘",
        "Deposit: harvest> deposit <amount>",
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
      print("Connect your wallet first. Tap 'connect wallet' below.", "");
      return;
    }

    if (!isVerified) {
      print(
        `Deposit ${formatUSDC(amount)} USDC requested.`,
        "World ID verification required first — opening IDKit...",
        ""
      );
      print(`Signal (wallet): ${walletAddress}`);
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
    print(
      "Harvester Agent",
      "  Status:         ● ACTIVE",
      "  Last harvest:   never",
      "  Next check:     in ~6h",
      "  Pending yield:  0 WLD",
      ""
    );
  }

  async function handleAgentHarvest() {
    print("Triggering manual harvest...");
    // TODO: POST /api/harvest (calls strategy.harvest() via agent wallet)
    print("No pending rewards above threshold.", "");
  }

  // ── IDKit flow ───────────────────────────────────────────────────────────────

  async function openIdkit() {
    try {
      const res = await fetch("/api/sign-request");
      if (!res.ok) throw new Error("Failed to fetch RP signature");
      const ctx: RpContext = await res.json();
      setRpContext(ctx);
      setIdkitOpen(true);
    } catch {
      print("Error: Could not initialize World ID verification.", "");
      setPendingDeposit(null);
    }
  }

  async function handleVerify(result: IDKitResult): Promise<void> {
    const res = await fetch("/api/verify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(result),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err?.detail ?? "Verification failed");
    }
  }

  const handleIdkitSuccess = useCallback(
    async (result: IDKitResult) => {
      setIdkitOpen(false);
      print("World ID verified. Registering on-chain...");

      if (!MiniKit.isInstalled()) {
        print("Error: MiniKit not available.", "");
        return;
      }

      try {
        // Debug: show raw result structure
        print(`IDKit result keys: ${JSON.stringify(Object.keys(result))}`);
        print(`Responses count: ${result.responses?.length ?? "undefined"}`);

        const response = result.responses[0];
        if (!response) {
          print("Error: No credential response from World ID.", "");
          print(`Full result: ${JSON.stringify(result).slice(0, 200)}`);
          return;
        }

        print(`Response keys: ${JSON.stringify(Object.keys(response))}`);

        let root: bigint;
        let nullifierHash: bigint;
        let proofArray: readonly [bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint];

        if ("merkle_root" in response) {
          // V3 legacy format
          const v3 = response as ResponseItemV3;
          root = BigInt(v3.merkle_root);
          nullifierHash = BigInt(v3.nullifier);
          const decoded = decodeProof(v3.proof);
          proofArray = decoded.map((d) => BigInt(d)) as unknown as typeof proofArray;
          print(`V3 format — root: ${root.toString().slice(0, 10)}...`);
        } else if ("nullifier" in response) {
          const v4 = response as ResponseItemV4;
          root = BigInt(v4.proof[4]);
          nullifierHash = BigInt(v4.nullifier);
          const elements = v4.proof.slice(0, 4).map((p) => BigInt(p));
          while (elements.length < 8) elements.push(BigInt(0));
          proofArray = elements as unknown as typeof proofArray;
          print(`V4 format — root: ${root.toString().slice(0, 10)}...`);
        } else {
          print("Error: Unsupported proof format.", "");
          print(`Response: ${JSON.stringify(response).slice(0, 200)}`);
          return;
        }

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

        print(`sendTransaction result: ${JSON.stringify(data).slice(0, 200)}`);

        if (data.status !== "success") {
          print(`Error: tx failed — status=${data.status}`, "");
          return;
        }

        setIsVerified(true);
        print(
          `Verified. UserOp: ${data.userOpHash.slice(0, 10)}...`,
          ""
        );

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
    [pendingDeposit, print]
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
    if (!walletAddress) {
      return [{ label: "connect wallet", action: () => {
        async function connect() {
          try {
            const result = await MiniKit.walletAuth({
              nonce: crypto.randomUUID().replace(/-/g, ""),
              statement: "Sign in to Harvest",
            });
            if (result?.data?.address) {
              setWalletAddress(result.data.address);
              print(`Connected: ${result.data.address.slice(0, 6)}...${result.data.address.slice(-4)}`, "");
            }
          } catch {
            print("Error: Could not connect wallet.", "");
          }
        }
        connect();
      }}];
    }
    if (!isVerified) {
      return [
        { label: "vaults", action: () => handleCommand("vaults") },
        { label: "deposit 50", action: () => handleCommand("deposit 50") },
        { label: "help", action: () => handleCommand("help") },
      ];
    }
    return [
      { label: "deposit 50", action: () => handleCommand("deposit 50") },
      { label: "portfolio", action: () => handleCommand("portfolio") },
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

      {/* IDKit widget — rendered but only opened when needed */}
      {rpContext && (
        <IDKitRequestWidget
          app_id={APP_ID}
          action="verify-human"
          rp_context={rpContext}
          allow_legacy_proofs={true}
          preset={orbLegacy({ signal: walletAddress ?? undefined })}
          open={idkitOpen}
          onOpenChange={setIdkitOpen}
          handleVerify={handleVerify}
          onSuccess={handleIdkitSuccess}
          onError={(errorCode: IDKitErrorCodes) => {
            print(`World ID error: ${errorCode}`, "");
            setIdkitOpen(false);
            setPendingDeposit(null);
          }}
        />
      )}
    </div>
  );
}
