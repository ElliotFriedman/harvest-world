# Harvest Mini App -- Infrastructure Setup Checklist
## ETHGlobal Cannes (April 3-5, 2026) -- 36-Hour Hackathon

**App:** Harvest -- Yield Aggregator on World Chain
**Target:** Deployed, functional, and submitted to World App Mini App Store by end of hackathon

---

## CRITICAL FINDING: Mainnet Required

The World Mini App FAQ explicitly states: **"Mini apps must be developed on mainnet rather than testnet."** MiniKit only functions inside World App, and the app store listing requires a live mainnet deployment. Plan accordingly -- you will need real (small) ETH on World Chain mainnet (chain ID 480) for contract deployment, though user transactions are gas-sponsored by World App's paymaster.

---

## PHASE 0: DO RIGHT NOW (Before Hackathon Starts)
*Estimated time: 2-3 hours. These are blocking dependencies for everything else.*

### World Developer Portal

- [ ] **Create World Developer Portal account**
  - URL: https://developer.worldcoin.org
  - Click "Create an account" and sign up
  - Time: 5 minutes
  - Blocking: Everything else in the portal
  - Who: Team lead

- [ ] **Register a new app ("Harvest")**
  - In the Developer Portal, create a new application
  - This generates your `app_id` (format: `app_xxxxxxxxxx`)
  - Configure the app name, description
  - Set the app URL to your deployment URL (can update later)
  - Time: 10 minutes
  - Blocking: MiniKit initialization, wallet auth, transaction whitelisting, notifications
  - Who: Team lead

- [ ] **Confirm someone on the team is Orb-verified in World App**
  - Required for: AgentKit wallet registration (QR scan verification flow)
  - Required for: Testing mini apps (MiniKit only works inside World App)
  - If nobody is verified, you can still build/deploy but cannot test inside World App or register agents
  - Time: N/A (must already be done)
  - Blocking: AgentKit registration, live testing
  - Who: Whoever has a verified World App account

### GitHub Repository

- [ ] **Create GitHub repository**
  - Recommended: **Monorepo** structure (hackathon = speed over separation)
  - Suggested name: `harvest-world` or `harvest-miniapp`
  - Initialize with the World Mini App template:
    ```bash
    npx @worldcoin/create-mini-app@latest harvest
    ```
  - Follow prompts, select `pnpm` as package manager
  - Time: 10 minutes
  - Blocking: All development
  - Who: Lead dev

- [ ] **Recommended repo structure:**
  ```
  harvest/
  ├── apps/
  │   └── web/              # Next.js 15 mini app (from template)
  ├── contracts/            # Foundry project
  │   ├── src/              # Solidity contracts (Vault, Strategy, etc.)
  │   ├── test/
  │   ├── script/
  │   └── foundry.toml
  ├── agent/                # Harvester agent (if separate)
  ├── .env.example
  ├── .gitignore
  └── package.json          # Root workspace config
  ```
  - For a 36-hour hackathon: skip branch protection, skip CI/CD, push directly to main
  - Time: 15 minutes
  - Who: Lead dev

### Domain & DNS

- [ ] **Purchase a domain (OPTIONAL but recommended)**
  - The World Developer Portal requires an **app URL** (your deployed frontend). A Vercel `.vercel.app` subdomain works for hackathon purposes.
  - A custom domain is NOT strictly required for the mini app store listing.
  - If you want one for polish:
    - Suggested: `harvestyield.xyz` (~$2-5/yr), `getharvest.app` (~$12/yr), `harvest-defi.xyz`
    - Registrars: Namecheap, Cloudflare Registrar, or Google Domains
    - `.xyz` domains are cheapest at ~$2-5/year
  - ENS name: Not needed for hackathon
  - Time: 15 minutes if purchasing
  - Blocking: Nothing (Vercel subdomain works fine)
  - Who: Anyone

### Deployer Wallet

- [ ] **Generate a deployer wallet (EOA)**
  - Use Foundry:
    ```bash
    cast wallet new
    ```
  - Save the private key securely (password manager, NOT in git)
  - This wallet will deploy contracts to World Chain mainnet
  - Time: 2 minutes
  - Blocking: Contract deployment
  - Who: Smart contract dev

- [ ] **Fund the deployer wallet with ETH on World Chain mainnet**
  - World Chain mainnet (chain ID: 480) requires real ETH for deployment gas
  - Options to get ETH on World Chain:
    1. Bridge from Ethereum mainnet: https://worldchain-mainnet.bridge.alchemy.com (slow, 7-day withdrawal)
    2. Bridge from another L2 via third-party bridges
    3. Send from an exchange that supports World Chain direct deposits
    4. Transfer from a funded wallet
  - You need very little ETH -- contract deployment costs are minimal on L2
  - Estimate: 0.005-0.01 ETH should be more than enough (~$15-30)
  - Time: 15-30 minutes (depends on bridge/transfer method)
  - Blocking: Contract deployment
  - Who: Smart contract dev / whoever has ETH

- [ ] **(Optional) Also fund a testnet wallet for initial development**
  - Faucet: https://www.alchemy.com/faucets/world-chain-sepolia
  - Gives 0.1 ETH per request, once per 24 hours
  - Requirement: Wallet must hold >= 0.001 ETH on Ethereum mainnet
  - World Chain Sepolia chain ID: 4801
  - RPC: `https://worldchain-sepolia.g.alchemy.com/public`
  - Testnet faucet for WLD tokens: https://l2faucet.com/world
  - Time: 5 minutes
  - Who: Smart contract dev

### API Keys

- [ ] **Alchemy API Key (RPC provider)**
  - URL: https://www.alchemy.com/world-chain
  - Sign up for free tier (300M compute units/month -- more than sufficient)
  - Create a World Chain app to get a dedicated RPC endpoint
  - The public endpoint (`https://worldchain-mainnet.g.alchemy.com/public`) works but has rate limits
  - A dedicated key is recommended for reliability
  - Time: 10 minutes
  - Blocking: Reliable RPC access
  - Who: Any dev

- [ ] **OpenAI or Anthropic API Key (for AI layer, if applicable)**
  - OpenAI: https://platform.openai.com/api-keys (pay-as-you-go, ~$5-20 for hackathon usage)
  - Anthropic: https://console.anthropic.com (pay-as-you-go)
  - Only needed if Harvest includes an AI-powered strategy recommendation or chatbot layer
  - Time: 5 minutes
  - Blocking: AI features only
  - Who: AI/agent dev

---

## PHASE 1: FIRST HOURS OF HACKATHON (Hours 0-6)
*Set up all infrastructure while contracts are being written.*

### Vercel Deployment

- [ ] **Create Vercel project**
  - URL: https://vercel.com
  - Import your GitHub repo
  - Framework preset: Next.js
  - Root directory: `apps/web` (if monorepo) or project root
  - Free tier ("Hobby"): **Sufficient for hackathon** -- includes custom domains, serverless functions, edge functions, 100GB bandwidth
  - Time: 10 minutes
  - Blocking: Live testing in World App
  - Who: Frontend dev

- [ ] **Configure Vercel environment variables**
  - Required variables (set in Vercel Dashboard > Project > Settings > Environment Variables):
    ```
    # World App (Developer Portal → Configuration)
    NEXT_PUBLIC_APP_ID=app_...           # Mini App ID
    WORLD_RP_ID=rp_...                   # RP ID for IDKit
    RP_SIGNING_KEY=0x...                 # Server-only signing key (never expose to browser)

    # Contracts — World Chain mainnet (chainId 480)
    NEXT_PUBLIC_VAULT_ADDRESS=0x512ce44e4f69a98bc42a57ced8257e65e63cd74f  # Harvest vault proxy

    # RPC — server-only (used by /api/balances)
    RPC_URL=https://worldchain-mainnet.g.alchemy.com/v2/YOUR_ALCHEMY_KEY

    # Agent wallet — server-only (used by /api/agent/harvest)
    AGENT_PRIVATE_KEY=0x...
    ```
  - See `app/.env.example` for the full reference with comments.
  - Time: 15 minutes
  - Blocking: Functional deployment
  - Who: Frontend dev

- [ ] **Link custom domain (if purchased)**
  - Vercel Dashboard > Project > Settings > Domains
  - Add your domain, configure DNS (A record or CNAME as Vercel instructs)
  - SSL is automatic
  - Time: 10 minutes
  - Who: Frontend dev

- [ ] **Set up local development tunnel for testing**
  - Install ngrok: `brew install ngrok` or `npm install -g ngrok`
  - Run: `ngrok http 3000`
  - Use the generated HTTPS URL in the Developer Portal as your app URL during development
  - Alternative tunneling: `zrok` or `tunnelmole`
  - Time: 5 minutes
  - Blocking: Testing in World App during development
  - Who: Frontend dev

### World Developer Portal Configuration

- [ ] **Configure app URL in Developer Portal**
  - Set to your Vercel deployment URL (e.g., `https://harvest-xxx.vercel.app`)
  - Or ngrok URL during local development
  - This is the URL World App loads in its webview
  - Time: 2 minutes
  - Who: Team lead

- [ ] **Set up World ID action (if using World ID verification)**
  - In Developer Portal > App > Actions
  - Create an action (e.g., `verify-human` for Sybil resistance on deposits)
  - Configure verification level (Orb, Device, or Phone)
  - Time: 5 minutes
  - Who: Team lead

- [ ] **Whitelist contracts and tokens (CRITICAL -- do after contract deployment)**
  - Developer Portal > Mini App > Permissions
  - Two categories to whitelist:
    1. **Permit2 Tokens**: Every ERC-20 your app transfers (WLD, USDC, WETH, etc.)
    2. **Contract Entrypoints**: Every contract your app calls (Vault, Strategy, Router, etc.)
  - **Transactions touching non-whitelisted contracts/tokens will fail** with `invalid_contract` error
  - Permit2 address on World Chain: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
  - Time: 10 minutes (after contracts are deployed)
  - Blocking: ALL user transactions from World App
  - Who: Team lead + smart contract dev

- [ ] **Configure notification permissions (optional)**
  - Developer Portal > App > Advanced Settings
  - Enable notification permissions
  - Unverified apps limited to 40 notifications per 4 hours (enough for hackathon demo)
  - Get API key for programmatic notification sending
  - Time: 5 minutes
  - Who: Team lead

### Agent State File

- [ ] **Ensure agent writes harvest state to `agent/last-harvest.json`**
  - The cron job writes a JSON file after each successful harvest:
    ```json
    {
      "lastRun": "2026-04-04T12:00:00Z",
      "lastTxHash": "0x...",
      "rewardsClaimed": "12.34",
      "profitUsd": "12.34",
      "status": "success"
    }
    ```
  - The `agent status` terminal command reads this file via a server route
  - No database needed — flat file is sufficient for hackathon
  - Time: already handled in agent code
  - Who: Agent dev

---

## PHASE 2: DURING DEVELOPMENT (Hours 6-24)

### Smart Contract Deployment

- [ ] **Deploy contracts to World Chain mainnet**
  - Using Foundry:
    ```bash
    forge create src/HarvestVault.sol:HarvestVault \
      --rpc-url https://worldchain-mainnet.g.alchemy.com/v2/YOUR_KEY \
      --private-key YOUR_DEPLOYER_KEY \
      --verify
    ```
  - Deploy all contracts: Vault, Strategy adapters, Router (if applicable)
  - Save all deployed addresses
  - Time: 30-60 minutes (including debugging)
  - Blocking: Frontend integration, contract whitelisting
  - Who: Smart contract dev

- [ ] **Verify contracts on block explorers**
  - WorldScan (Etherscan-based): https://worldscan.org
  - Blockscout: https://worldchain-mainnet.explorer.alchemy.com/
  - Use `--verify` flag during deployment, or verify manually:
    ```bash
    forge verify-contract CONTRACT_ADDRESS src/HarvestVault.sol:HarvestVault \
      --chain-id 480 \
      --etherscan-api-key YOUR_WORLDSCAN_KEY
    ```
  - Time: 15 minutes
  - Who: Smart contract dev

- [ ] **Whitelist deployed contracts in Developer Portal (IMMEDIATELY after deploy)**
  - Go to Developer Portal > Mini App > Permissions
  - Add each contract address under "Contract Entrypoints"
  - Add each ERC-20 token under "Permit2 Tokens"
  - Key token addresses on World Chain mainnet:
    - WLD: `0x2cfc85d8e48f8eab294be644d9e25c3030863003`
    - USDC: `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1`
    - WETH: `0x4200000000000000000000000000000000000006`
    - WBTC: `0x03c7054bcb39f7b2e5b2c7acb37583e32d70cfa3`
    - sDAI: `0x859dbe24b90c9f2f7742083d3cf59ca41f55be5d`
  - Time: 10 minutes
  - Blocking: All user-facing transactions
  - Who: Team lead

### AgentKit Setup (If Using Automated Harvester Agent)

- [ ] **Generate agent/harvester wallet (EOA)**
  - This is the wallet the harvester bot uses to call `harvest()` on strategies
  - Generate with: `cast wallet new`
  - Fund with small amount of ETH for gas (the agent calls contracts, not users)
  - For hackathon: EOA with private key is fine (no multisig needed)
  - Store private key in environment variable, never commit to git
  - Time: 5 minutes
  - Who: Agent dev

- [ ] **Register agent wallet via AgentKit CLI**
  - Install:
    ```bash
    npm install @worldcoin/agentkit
    ```
  - Register:
    ```bash
    npx @worldcoin/agentkit-cli register <agent-wallet-address>
    ```
  - This process:
    1. Looks up the next nonce for the agent address
    2. Prompts World App verification flow (QR code scan)
    3. Submits the registration transaction
  - **Requires**: Someone with World App on their phone to scan the QR code
  - **Requires**: That person must be Orb-verified
  - Time: 10 minutes
  - Blocking: AgentKit functionality
  - Who: Agent dev + Orb-verified team member

- [ ] **Add AgentKit skill**
  - After registration:
    ```bash
    npx skills add worldcoin/agentkit agentkit-x402
    ```
  - Supported networks: WorldChain (eip155:480) with USDC, Base (eip155:8453)
  - Time: 5 minutes
  - Who: Agent dev

### Wallet / Key Management

- [ ] **Document all keys and who holds them**
  - For a hackathon, a shared password manager entry (1Password, Bitwarden) or a shared encrypted note is fine
  - Keys to track:
    - Deployer wallet private key
    - Agent/harvester wallet private key
    - Alchemy API key
    - Developer Portal API key
    - OpenAI/Anthropic API key (if used)
  - **EOA is fine for hackathon** -- no multisig (Safe) needed
  - If you want a multisig post-hackathon: https://app.safe.global (supports World Chain)
  - Time: 10 minutes
  - Who: Team lead

---

## PHASE 3: PRE-SUBMISSION (Hours 24-32)

### Mini App Store Listing Preparation

- [ ] **Prepare visual assets**

  **App Icon:**
  - Square image
  - Non-white background (required)
  - Clean, recognizable at small sizes
  - Format: PNG
  - Suggestion: Simple harvest/yield themed icon (wheat sheaf, upward graph, etc.)
  - Time: 30 minutes
  - Who: Designer or frontend dev

  **Content Card:**
  - Dimensions: **345 x 240 pixels** (at 1x; provide at 3x scale = 1035 x 720 pixels)
  - Bottom 94 pixels (at 1x; 282 pixels at 3x) are overlaid with text/metadata -- keep that area minimal
  - Minimal text within the image itself
  - Format: **PNG at 3x scale**
  - No border radius (the store applies it)
  - Time: 30 minutes
  - Who: Designer or frontend dev

- [ ] **Write app metadata**
  - **App name:** "Harvest" (do NOT use "World" in the name -- will be rejected)
  - **Description:** Max 25 words, no spammy language or special characters
    - Example: "Maximize your World Chain yields. Discover, deposit, and auto-compound across DeFi protocols with one-tap simplicity."
  - **Category:** Finance / DeFi (select the closest available category)
  - Time: 15 minutes
  - Who: Team lead

- [ ] **Ensure compliance with app guidelines (REJECTION CHECKLIST)**
  - [ ] NO chance-based games or RNG-determined prizes
  - [ ] NO token pre-sales
  - [ ] NO paid memberships granting yield/return increases
  - [ ] NO use of "official" in naming or descriptions
  - [ ] NO World logos or modified World branding
  - [ ] NO NFT purchase buttons (viewing personal NFTs only)
  - [ ] Display **usernames**, never raw wallet addresses
  - [ ] Performance: Initial load under 2-3 seconds, actions under 1 second
  - [ ] Mobile-first, responsive design
  - [ ] Tab-based navigation (not hamburger menus)
  - [ ] CSS: `overscroll-behavior: none`, use `100dvh` not `100vh`
  - [ ] Loading states / visual feedback for all actions
  - [ ] Localization support (at minimum: English; ideal: Spanish, Thai, Japanese, Korean, Portuguese)
  - Time: 1-2 hours (verification pass)
  - Blocking: Approval
  - Who: Entire team

### Testing

- [ ] **Test in World App on a real device**
  - MiniKit ONLY works inside World App (not in a browser)
  - Use the QR code testing flow:
    1. Enter your `app_id` in the testing tool
    2. Scan the QR code with your phone camera
    3. Confirm the prompt in World App
  - Test all flows: wallet auth, deposits, withdrawals, harvest triggers
  - Use Eruda for mobile console debugging: include in dev builds
  - Time: 2-4 hours
  - Who: Entire team, especially the person with World App

- [ ] **Debug failed transactions**
  - Use the Transaction Debug URL endpoint:
    ```
    GET /api/v2/minikit/userop/{userOpHash}
    ```
  - Common errors:
    - `invalid_contract`: Contract/token not whitelisted -- fix in Developer Portal
    - `simulation_failed`: Contract logic error -- debug the contract
    - `daily_tx_limit_reached`: User hit daily transaction cap
  - Time: Ongoing
  - Who: Smart contract dev + frontend dev

---

## PHASE 4: SUBMISSION (Hours 32-36)

### Submit to World App Mini App Store

- [ ] **Submit app through Developer Portal**
  - Developer Portal > Your App > Submit for Review
  - Ensure all fields are complete:
    - App name
    - Description (max 25 words)
    - App icon (square, non-white background)
    - Content card (345x240 at 1x, PNG at 3x)
    - App URL (your Vercel production URL)
    - All contracts whitelisted
  - Time: 15 minutes
  - Blocking: N/A (end of pipeline)
  - Who: Team lead

- [ ] **Understand the review process**
  - **Review is required** before public listing
  - Timeline: "As quickly as possible" -- no guaranteed SLA
  - Complex apps may take longer
  - **No documented expedited process for hackathons**
  - Rejection reasons are communicated via email and portal
  - If rejected, fix issues and resubmit (repeated failures for same issue = longer subsequent reviews)
  - Contact for rejected apps: **@MateoSauton on Telegram**
  - **For hackathon judging:** You likely won't be publicly listed during the hackathon. Judges can test via the QR code / direct URL in World App. Submit anyway to show intent and process completion.
  - Who: Team lead

---

## COMPLETE API KEY / ACCOUNT INVENTORY

| Service | Key Type | Free Tier Sufficient? | URL | Notes |
|---------|----------|----------------------|-----|-------|
| World Developer Portal | App ID + API Key | Yes (free) | https://developer.worldcoin.org | Required. API key for notifications & verification |
| Alchemy | API Key | Yes (300M CU/month) | https://www.alchemy.com/world-chain | RPC provider. Public endpoint exists as fallback |
| Vercel | N/A (GitHub integration) | Yes (Hobby tier) | https://vercel.com | Hosting, serverless, custom domains |
| OpenAI | API Key | Pay-as-you-go (~$5-20) | https://platform.openai.com | Only if AI features used |
| Anthropic | API Key | Pay-as-you-go (~$5-20) | https://console.anthropic.com | Alternative to OpenAI |
| Merkl | None needed | Yes (public API) | https://api.merkl.xyz | Public API, no key required |
| DeFi Llama | None needed | Yes (public API) | https://defillama.com/docs/api | Public API, no key required |
| WorldScan | API Key (optional) | Yes | https://worldscan.org | For contract verification. Etherscan-compatible API |

---

## WORLD CHAIN QUICK REFERENCE

| Parameter | Mainnet | Sepolia Testnet |
|-----------|---------|-----------------|
| Chain ID | 480 (0x1e0) | 4801 (0x12C1) |
| RPC (Public) | https://worldchain-mainnet.g.alchemy.com/public | https://worldchain-sepolia.g.alchemy.com/public |
| Block Explorer (WorldScan) | https://worldscan.org | https://sepolia.worldscan.org |
| Block Explorer (Blockscout) | https://worldchain-mainnet.explorer.alchemy.com | https://worldchain-sepolia.explorer.alchemy.com |
| Bridge | https://worldchain-mainnet.bridge.alchemy.com | https://worldchain-sepolia.bridge.alchemy.com |
| Faucet | N/A | https://www.alchemy.com/faucets/world-chain-sepolia |
| WLD Faucet | N/A | https://l2faucet.com/world |
| Block Time | 2 seconds | 2 seconds |
| Framework | OP Stack (Superchain) | OP Stack (Superchain) |

### Key Mainnet Contract Addresses

| Contract | Address |
|----------|---------|
| WLD | `0x2cfc85d8e48f8eab294be644d9e25c3030863003` |
| USDC | `0x79A02482A880bCE3F13e09Da970dC34db4CD24d1` |
| WETH | `0x4200000000000000000000000000000000000006` |
| WBTC | `0x03c7054bcb39f7b2e5b2c7acb37583e32d70cfa3` |
| sDAI | `0x859dbe24b90c9f2f7742083d3cf59ca41f55be5d` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| WLD/USD Oracle | `0x8Bb2943AB030E3eE05a58d9832525B4f60A97FA0` |
| ETH/USD Oracle | `0xe1d72a719171DceAB9499757EB9d5AEb9e8D64A6` |
| World ID Router | `0x17B354dD2595411ff79041f930e491A4Df39A278` |
| Entrypoint v0.7 (AA) | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` |

---

## COST SUMMARY (Hackathon Budget)

| Item | Cost | Required? |
|------|------|-----------|
| Domain (.xyz) | $2-5/year | No (Vercel subdomain works) |
| ETH for deployment (World Chain mainnet) | ~$15-30 in ETH | Yes |
| ETH for agent wallet gas | ~$5-10 in ETH | Yes (if using agent) |
| Alchemy | Free | Yes |
| Vercel | Free | Yes |
| World Developer Portal | Free | Yes |
| OpenAI/Anthropic credits | ~$5-20 | Only if AI features |
| **TOTAL** | **~$25-65** | |

---

## HACKATHON-SPECIFIC NOTES

1. **Skip multisig / Safe setup.** EOA wallets are fine for a 36-hour build. You can migrate to a Safe multisig post-hackathon.

2. **Skip branch protection and CI/CD.** Push to main. Move fast.

3. **Skip extensive localization.** English-only is acceptable for demo. Add localization post-hackathon for store approval.

4. **The app store listing will NOT be approved during the hackathon.** Plan your demo around the QR-code testing flow or direct URL loading in World App. Submit to the store anyway as a signal of completion.

5. **MiniKit v2 is current.** Use `@worldcoin/minikit-js` latest. Key differences from v1: async methods, SIWE-based wallet auth, calldata-style transactions with `chainId: 480`.

6. **Permit2 pattern is mandatory.** World App uses Permit2 AllowanceTransfers. Your vault contracts must call `permit2.transferFrom()` -- users do not do separate token approvals. Token approval to Permit2 is handled automatically by World App.

7. **UserOpHash, not tx hash.** `MiniKit.sendTransaction()` returns a `userOpHash`. Poll `GET /api/v2/minikit/userop/{userOpHash}` to get the final `transaction_hash` once mined.

8. **Contact for urgent help:** World Developer Support on Telegram: @worlddevelopersupport. For app review issues: @MateoSauton on Telegram.
