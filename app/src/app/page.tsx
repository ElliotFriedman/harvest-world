"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import type { IDKitResult, IDKitErrorCodes, RpContext } from "@worldcoin/idkit";
import { MiniKit } from "@worldcoin/minikit-js";
import { encodeFunctionData } from "viem";
import { getBalances, getVaultTvl, getAgentStatus, triggerHarvest } from "../lib/client";

// Lazy-load IDKit to prevent crashes in World App webview
const LazyIDKit = dynamic(
  () => import("../components/idkit-widget"),
  { ssr: false }
);

// ─── Constants ───────────────────────────────────────────────────────────────

const APP_ID = process.env.NEXT_PUBLIC_APP_ID as `app_${string}`;
const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ??
  "0x0000000000000000000000000000000000000000") as `0x${string}`;
const USDC_ADDRESS = "0x79A02482A880bCE3F13e09Da970dC34db4CD24d1" as const;
const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3" as const;
const WORLD_CHAIN_ID = 480;

// Minimal ABIs for on-chain calls
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

function formatUSDC(amount: number): string {
  return amount.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatBigintUSDC(raw: bigint): string {
  const whole = raw / BigInt(1e6);
  const frac = raw % BigInt(1e6);
  const fracStr = frac.toString().padStart(6, "0").slice(0, 2);
  return `${whole.toLocaleString()}.${fracStr}`;
}

// ─── Component ────────────────────────────────────────────────────────────────

export default function Terminal() {
  const [lines, setLines] = useState<string[]>([
    "HARVEST v2.4 — Agentic DeFi, for humans.",
    "World Chain yield aggregator.",
    "",
  ]);
  const [input, setInput] = useState("");
  const [pendingDeposit, setPendingDeposit] = useState<number | null>(null);
  const [idkitOpen, setIdkitOpen] = useState(false);
  const [rpContext, setRpContext] = useState<RpContext | null>(null);
  const [walletAddress, setWalletAddress] = useState<string | null>(null);
  const [isVerified, setIsVerified] = useState(false);
  const [hasShares, setHasShares] = useState(false);
  const [depositMode, setDepositMode] = useState(false);
  const [usdcBalance, setUsdcBalance] = useState<bigint>(BigInt(0));
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  useEffect(() => {
    if (!MiniKit.isInstalled()) return;
    if (MiniKit.user?.walletAddress) {
      setWalletAddress(MiniKit.user.walletAddress);
    }
  }, []);

  const print = useCallback((...newLines: string[]) => {
    setLines((prev) => [...prev, ...newLines]);
  }, []);

  async function typewriterPrint(text: string, delayMs = 28): Promise<void> {
    setLines((prev) => [...prev, ""]);
    for (let i = 1; i <= text.length; i++) {
      await new Promise<void>((resolve) => setTimeout(resolve, delayMs));
      setLines((prev) => {
        const updated = [...prev];
        updated[updated.length - 1] = text.slice(0, i);
        return updated;
      });
    }
  }

  // ── Command handlers ────────────────────────────────────────────────────────

  async function handleHelp() {
    print(
      "Commands:",
      "  vaults         — list vaults + APY",
      "  deposit <n>    — deposit USDC",
      "  withdraw all   — exit position",
      "  portfolio      — your balance",
      "  agent status   — harvester info",
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
        `  APY:    4.23%`,
        `  TVL:    $${tvlFormatted}`,
        `  Status: LIVE`,
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

    // Check balance before proceeding
    try {
      const { usdcBalance: bal } = await getBalances(walletAddress);
      setUsdcBalance(bal);
      const balanceUSD = Number(bal) / 1e6;
      if (amount > balanceUSD) {
        print(
          `Insufficient balance: you have $${formatUSDC(balanceUSD)} USDC.`,
          balanceUSD > 0
            ? `Try 'deposit ${Math.floor(balanceUSD)}' or tap deposit for options.`
            : "Top up your wallet first.",
          ""
        );
        return;
      }
    } catch {
      // balance check failed — let the tx attempt and fail naturally
    }

    if (!isVerified) {
      print(
        `Deposit ${formatUSDC(amount)} USDC requested.`,
        "World ID verification required first...",
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
      print("Error: Open this app inside World App.", "");
      return;
    }

    if (!walletAddress) {
      print("Error: Wallet not connected.", "");
      return;
    }

    if (!isVerified) {
      print("Error: World ID verification required first.", "");
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
      print(`Error: ${err instanceof Error ? err.message : "unknown"}`, "");
    }
  }

  async function handlePortfolio() {
    if (!walletAddress) {
      print("Connect via World App to view your portfolio.", "");
      return;
    }

    print(`Loading portfolio...`);

    try {
      const { usdcBalance, vaultShares, pricePerShare } = await getBalances(walletAddress);

      if (vaultShares > BigInt(0)) setHasShares(true);

      const vaultUsdValue = (vaultShares * pricePerShare) / BigInt(1e18);
      const totalUsdValue = usdcBalance + vaultUsdValue;

      print(
        `Portfolio for ${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`,
        `  USDC in wallet: $${formatBigintUSDC(usdcBalance)}`,
        `  Vault shares:   ${formatBigintUSDC(vaultShares)} hvUSDC`,
        `  Vault USD value: $${formatBigintUSDC(vaultUsdValue)}`,
        `  Total USD value: $${formatBigintUSDC(totalUsdValue)}`,
        ""
      );
    } catch {
      print("Error loading portfolio. Try again.", "");
    }
  }

  async function handleAgentStatus() {
    print("Loading agent status...");
    try {
      const s = await getAgentStatus();

      const lastHarvestStr = s.lastHarvest
        ? `${new Date(s.lastHarvest.timestamp).toLocaleString()} (+$${s.lastHarvest.wantEarned})`
        : "never";

      const nextCheckStr = (() => {
        const ms = new Date(s.nextCheck).getTime() - Date.now();
        if (ms <= 0) return "soon";
        const h = Math.floor(ms / 3600_000);
        const m = Math.floor((ms % 3600_000) / 60_000);
        return h > 0 ? `in ~${h}h` : `in ~${m}m`;
      })();

      const poolUSD = s.balanceOfPool
        ? `$${(Number(s.balanceOfPool) / 1e6).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
        : "--";

      const rewardStr = s.pendingRewards
        ? `${s.pendingRewards.amount} ($${s.pendingRewards.usdValue.toFixed(2)})`
        : "0 WLD";

      const swapEstimate = s.uniswapQuote
        ? `~${s.uniswapQuote.expectedOutput} (impact: ${s.uniswapQuote.priceImpact}%)`
        : "";

      print(
        "HARVESTER AGENT",
        `  Status:         ● ${s.status.toUpperCase()}`,
        `  Pool balance:   ${poolUSD}`,
        `  Pending yield:  ${rewardStr}`,
        ...(swapEstimate ? [`  Swap estimate:  ${swapEstimate}`] : []),
        `  Last harvest:   ${lastHarvestStr}`,
        `  Next check:     ${nextCheckStr}`,
        ""
      );
    } catch {
      print("Error loading agent status. Try again.", "");
    }
  }

  async function handleAgentHarvest() {
    print("Triggering harvest...");
    try {
      const result = await triggerHarvest();
      if (result.success) {
        const quoteLine = result.uniswapQuote
          ? `  Swap quote:    ${result.uniswapQuote.expectedOutput} (via Uniswap ${result.uniswapQuote.routing})`
          : "";
        print(
          "Harvest complete.",
          result.wantEarned ? `  Yield earned:  +$${result.wantEarned}` : "",
          result.rewardsClaimed ? `  Rewards:       ${result.rewardsClaimed}` : "",
          ...(quoteLine ? [quoteLine] : []),
          result.txHash ? `  Tx: ${result.txHash.slice(0, 10)}...` : "",
          ""
        );
      } else {
        const reason = result.message ?? result.reason ?? "unknown";
        print(`Harvest skipped: ${reason}`, "");
      }
    } catch {
      print("Error triggering harvest. Try again.", "");
    }
  }

  // ── Easter egg ──────────────────────────────────────────────────────────────

  async function handleEasterEgg() {
    await typewriterPrint("* you found the easter egg. congrats. *");
    await new Promise((r) => setTimeout(r, 500));
    print("");
    await typewriterPrint("we wanted to add the wonder back into finance.");
    await new Promise((r) => setTimeout(r, 200));
    await typewriterPrint("the feeling of getting a new computer.");
    await new Promise((r) => setTimeout(r, 200));
    await typewriterPrint("and entering a whole new world...");
    await new Promise((r) => setTimeout(r, 600));
    print("");
    await typewriterPrint("we hope you enjoy :)");
    print("");
  }

  // ── Deposit picker flow ──────────────────────────────────────────────────────

  async function openDepositPicker() {
    if (!walletAddress) {
      print("Connect your wallet first. Tap 'get started'.", "");
      return;
    }
    print("harvest> deposit", "Checking balance...");
    try {
      const { usdcBalance: bal } = await getBalances(walletAddress);
      setUsdcBalance(bal);
      if (bal === BigInt(0)) {
        print("No USDC balance. Top up your wallet first.", "");
        return;
      }
      setDepositMode(true);
      print("Select amount:");
    } catch {
      print("Error: Could not fetch balance.", "");
    }
  }

  async function onDepositAmount(amount: number | "max") {
    setDepositMode(false);
    const resolvedAmount =
      amount === "max" ? Number(usdcBalance) / 1e6 : amount;
    print(`  → $${formatUSDC(resolvedAmount)}`);
    await handleDeposit([resolvedAmount.toString()]);
  }

  // ── IDKit flow (backend-only verification) ─────────────────────────────────

  async function openIdkit() {
    if (!walletAddress) {
      print("Error: Wallet must be connected first.", "");
      setPendingDeposit(null);
      return;
    }

    try {
      const res = await fetch("/api/sign-request");
      if (!res.ok) throw new Error("Failed to fetch RP signature");
      const ctx: RpContext = await res.json();
      setRpContext(ctx);
      setIdkitOpen(true);
    } catch {
      print("Error: Could not initialize verification.", "");
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
    async (_result: IDKitResult) => {
      setIdkitOpen(false);

      // Backend verified the proof via World ID API — that's sufficient.
      // No on-chain verifyHuman tx needed (V4 nullifiers exceed BN254 field).
      setIsVerified(true);
      print("World ID verified.", "");

      // Fetch balance after verification
      if (walletAddress) {
        try {
          const { usdcBalance, vaultShares } = await getBalances(walletAddress);
          if (vaultShares > BigInt(0)) setHasShares(true);
          if (usdcBalance === BigInt(0)) {
            print("Top up your wallet with USDC to deposit.", "");
          } else {
            print(`USDC balance: $${formatBigintUSDC(usdcBalance)}`, "");
            print("Type 'deposit <amount>' or tap below.", "");
          }
        } catch { /* ignore */ }
      }

      // If a deposit was waiting, execute it now
      if (pendingDeposit !== null) {
        const amount = pendingDeposit;
        setPendingDeposit(null);
        await executeDeposit(amount);
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
      const amountRaw = BigInt(Math.floor(amount * 1e6));

      // set to zero per world docs.
      const expiration = 0;
      const approveCalldata = encodeFunctionData({
        abi: PERMIT2_APPROVE_ABI,
        functionName: "approve",
        args: [USDC_ADDRESS, VAULT_ADDRESS, amountRaw, expiration],
      });

      const depositCalldata = encodeFunctionData({
        abi: DEPOSIT_ABI,
        functionName: "deposit",
        args: [amountRaw],
      });

      const { data } = await MiniKit.sendTransaction({
        chainId: WORLD_CHAIN_ID,
        transactions: [
          { to: PERMIT2_ADDRESS, data: approveCalldata },
          { to: VAULT_ADDRESS, data: depositCalldata },
        ],
      });

      if (data.status !== "success") {
        print(`Error: Deposit failed — ${data.status}`, "");
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
      print(`Error: ${err instanceof Error ? err.message : "unknown"}`, "");
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
        transactions: [{ to: VAULT_ADDRESS, data: withdrawCalldata }],
      });

      if (data.status !== "success") {
        print("Error: Withdrawal failed.", "");
        return;
      }

      print(
        "Withdrawal complete.",
        `  UserOp: ${data.userOpHash.slice(0, 10)}...`,
        "  Run 'portfolio' to see updated position.",
        ""
      );
    } catch (err) {
      print(`Error: ${err instanceof Error ? err.message : "unknown"}`, "");
    }
  }

  // ── Get Started flow ────────────────────────────────────────────────────────

  async function handleGetStarted() {
    if (!MiniKit.isInstalled()) {
      print("Open this app inside World App.", "");
      return;
    }

    print("Connecting wallet...");

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

    // Open IDKit for World ID verification
    print("Verifying humanity...");
    try {
      const res = await fetch("/api/sign-request");
      if (!res.ok) throw new Error("Failed to fetch RP signature");
      const ctx: RpContext = await res.json();
      setRpContext(ctx);
      setIdkitOpen(true);
    } catch {
      print("Error: Could not start verification.", "");
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
    } else if (trimmed === "easter egg") {
      await handleEasterEgg();
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

  function getButtons(): { label: string; action: () => void; disabled?: boolean }[] {
    // Deposit amount picker — shown after openDepositPicker() fetches the balance
    if (depositMode) {
      const balanceUSD = Number(usdcBalance) / 1e6;
      return [
        ...[10, 25, 50, 100].map((amt) => ({
          label: `$${amt}`,
          action: () => onDepositAmount(amt),
          disabled: amt > balanceUSD,
        })),
        {
          label: `MAX ($${formatUSDC(balanceUSD)})`,
          action: () => onDepositAmount("max"),
          disabled: false,
        },
        {
          label: "cancel",
          action: () => { setDepositMode(false); print("Cancelled.", ""); },
          disabled: false,
        },
      ];
    }

    if (!walletAddress || !isVerified) {
      return [{ label: "get started", action: handleGetStarted }];
    }
    if (hasShares) {
      return [
        { label: "deposit", action: openDepositPicker },
        { label: "portfolio", action: () => handleCommand("portfolio") },
        { label: "withdraw all", action: () => handleCommand("withdraw all") },
      ];
    }
    return [
      { label: "deposit", action: openDepositPicker },
      { label: "portfolio", action: () => handleCommand("portfolio") },
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
            onClick={btn.disabled ? undefined : btn.action}
            style={{
              background: "transparent",
              border: "1px solid #00ff41",
              color: "#00ff41",
              fontFamily: "inherit",
              fontSize: "11px",
              padding: "4px 8px",
              cursor: btn.disabled ? "default" : "pointer",
              opacity: btn.disabled ? 0.3 : 1,
            }}
          >
            {btn.label}
          </button>
        ))}
      </div>

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

      {/* IDKit v4 widget — backend verification only, no on-chain verifyHuman */}
      {rpContext && walletAddress && (
        <LazyIDKit
          appId={APP_ID}
          action="verify-human"
          rpContext={rpContext}
          walletAddress={walletAddress}
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
