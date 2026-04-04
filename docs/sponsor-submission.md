WORLD - $20,000

Why you're applicable:

Harvest integrates all three World SDKs as load-bearing components. World ID 4.0 (IDKit v4) gates vault deposits to Orb-verified humans — sybil-proof DeFi. AgentKit proves the harvester agent is human-backed via on-chain AgentBook verification. MiniKit powers atomic Permit2 approve+deposit transactions inside World App. Proof validation occurs in our web backend via the World ID v4 verify endpoint. $1,000+ in real mainnet deposits from verified World App users.

Links to code:

https://github.com/ElliotFriedman/harvest-world/blob/main/app/src/components/idkit-widget.tsx
https://github.com/ElliotFriedman/harvest-world/blob/main/app/src/app/api/sign-request/route.ts
https://github.com/ElliotFriedman/harvest-world/blob/main/app/src/app/page.tsx
https://github.com/ElliotFriedman/harvest-world/blob/main/agent/src/agentkit.ts
https://github.com/ElliotFriedman/harvest-world/blob/main/agent/src/index.ts

Ease of use: 8

Feedback:

IDKit v4 and MiniKit 2.0 were straightforward — good docs, clean SDK. The main pain point was the V3 to V4 World ID migration: orbLegacy() Merkle roots don't exist in the V4-migrated WorldIDRouter on mainnet, so on-chain verifyProof() fails. We had to fall back to backend-only verification. Documenting this migration path more clearly would help. AgentKit CLI registration was smooth. Permit2 requirement for MiniKit was initially confusing but makes sense for security.


UNISWAP FOUNDATION - $10,000

Why you're applicable:

Our AI harvester agent uses the Uniswap Trading API to quote WLD to USDC swaps before every harvest. The agent fetches a live quote, checks gas vs output profitability (skips if gas > 50% of output), then executes the swap through Uniswap V3 SwapRouter02 on World Chain. On-chain, the BeefySwapper routes WLD to WETH (0.3% pool) then WETH to USDC (0.05% pool) via exactInputSingle. Real harvest transactions verified on Worldscan.

Links to code:

https://github.com/ElliotFriedman/harvest-world/blob/main/app/src/lib/uniswap.ts#L5
https://github.com/ElliotFriedman/harvest-world/blob/main/contracts/script/Deploy.s.sol#L64
https://github.com/ElliotFriedman/harvest-world/blob/main/contracts/src/BeefySwapper.sol
https://github.com/ElliotFriedman/harvest-world/blob/main/agent/src/harvester.ts

Ease of use: 7

Feedback:

The Uniswap Trading API worked well for quoting. Getting the exactInputSingle calldata encoding right for the BeefySwapper was tricky — the byte offsets for amountIn (132) and minAmountOut (164) in the encoded calldata took trial and error. Having a reference implementation or encoding helper in the SDK for common swap patterns would save time. The Uniswap MCP / AI skill was useful during development for understanding V3 pool fee tiers and route design.
