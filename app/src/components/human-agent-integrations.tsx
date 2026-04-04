"use client";

/**
 * Harvest 品牌整合區塊 — 雙行同步掃描跑馬燈
 * Brand: bg #0a0a0a · Row1 Human Amber · Row2 Terminal Green
 */

import { useEffect, useMemo, useState } from "react";
import styles from "./human-agent-integrations.module.css";

const H1_TARGET = ">_ Discover Pure Yield. Pure Human.";
const TYPE_MS = 52;
/** 週期重打：每 N ms 清空並從頭打字 */
const RETYPE_INTERVAL_MS = 5000;

const row1Icons = [
  { name: "World Chain", id: "worldchain" },
  { name: "Ethereum", id: "eth" },
  { name: "World ID", id: "worldid" },
  { name: "Orb Verified", id: "orb" },
  { name: "Permit2", id: "permit2" },
  { name: "Next.js", id: "nextjs" },
  { name: "Foundry", id: "foundry" },
  { name: "Supabase", id: "supabase" },
] as const;

const row2Icons = [
  { name: "AgentKit", id: "agentkit" },
  { name: "AgentBook", id: "agentbook" },
  { name: "Morpho", id: "morpho" },
  { name: "Beefy", id: "beefy" },
  { name: "Uniswap", id: "uniswap" },
  { name: "Merkl", id: "merkl" },
  { name: "Vercel", id: "vercel" },
  { name: "Base", id: "base" },
] as const;

function worldAppConsoleUrl(appId: string | undefined): string {
  if (appId && appId.startsWith("app_")) {
    return `https://developer.worldcoin.org/app/${appId}`;
  }
  return "https://developer.worldcoin.org";
}

function HumanAgentIntegrations() {
  const [typed, setTyped] = useState("");
  const appId = process.env.NEXT_PUBLIC_APP_ID;
  const ctaHref = useMemo(() => worldAppConsoleUrl(appId), [appId]);

  useEffect(() => {
    if (typed.length >= H1_TARGET.length) return;
    const t = window.setTimeout(() => setTyped(H1_TARGET.slice(0, typed.length + 1)), TYPE_MS);
    return () => clearTimeout(t);
  }, [typed]);

  useEffect(() => {
    const id = window.setInterval(() => {
      setTyped("");
    }, RETYPE_INTERVAL_MS);
    return () => clearInterval(id);
  }, []);

  const r1 = [...row1Icons, ...row1Icons];
  const r2 = [...row2Icons, ...row2Icons];

  return (
    <section
      className="relative w-full overflow-hidden bg-terminal-dark py-14 font-harvest sm:py-24"
      aria-labelledby="integrations-hero-heading"
    >
      <div className="mx-auto mb-16 max-w-4xl px-6 sm:mb-20">
        <div className="mb-6 flex w-full justify-center">
          <div className="relative inline-block px-1">
            <div className={`${styles.crtScanlines} rounded-sm`} aria-hidden />
            <h1
              id="integrations-hero-heading"
              className={`relative whitespace-nowrap text-center text-4xl font-bold tracking-tight text-terminal-green md:text-6xl ${styles.h1Glow}`}
            >
              {typed}
              <span className="inline-block w-[0.6ch] animate-harvest-cursor-blink align-baseline">_</span>
            </h1>
          </div>
        </div>
        <p className="text-center text-xl text-soft-white/80 md:text-2xl">
          A new kind of DeFi experience. Human-first, bot-proof.
        </p>
      </div>

      {/* 跑馬燈可視區：約佔螢幕 1/5～4/5（寬度 60%，左右各留 20%） */}
      <div className="mx-auto flex min-w-0 w-3/5 max-w-full flex-col gap-8 opacity-90">
        {/* Row 1: Amber — 向左滾動 (translate 0 → -50%) */}
        <div
          className={`flex min-w-0 select-none overflow-hidden ${styles.marqueeFade}`}
        >
          <div className="flex w-max flex-nowrap animate-marquee-fast motion-reduce:animate-none hover:[animation-play-state:paused]">
            {r1.map((icon, i) => (
              <div
                key={`r1-${icon.id}-${i}`}
                className="mx-4 flex h-24 w-40 shrink-0 items-center justify-center rounded-harvest border border-muted-gray bg-deep-gray transition-all hover:border-human-amber"
              >
                <span className="text-center text-xs font-bold uppercase tracking-tighter text-human-amber">
                  {icon.name}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Row 2: Green — 向右滾動 */}
        <div className={`flex min-w-0 select-none overflow-hidden ${styles.marqueeFade}`}>
          <div className="flex w-max flex-nowrap animate-marquee-fast-reverse motion-reduce:animate-none hover:[animation-play-state:paused]">
            {r2.map((icon, i) => (
              <div
                key={`r2-${icon.id}-${i}`}
                className="mx-4 flex h-24 w-40 shrink-0 items-center justify-center rounded-harvest border border-muted-gray bg-deep-gray transition-all hover:border-terminal-green"
              >
                <span className="text-center text-xs font-bold uppercase tracking-tighter text-terminal-green">
                  {icon.name}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="mt-16 text-center sm:mt-20">
        <a
          href={ctaHref}
          target="_blank"
          rel="noopener noreferrer"
          className={`group relative inline-flex items-center justify-center rounded-harvest bg-human-amber px-10 py-4 font-bold text-harvest-cta text-terminal-dark transition-all hover:bg-[#ffb633] active:scale-95 ${styles.cta}`}
        >
          harvest_
        </a>
        <p className="mt-4 font-harvest text-xs text-muted-gray">
          Every depositor verified. Every harvest shared.
        </p>
      </div>
    </section>
  );
}

export { HumanAgentIntegrations };
export default HumanAgentIntegrations;
