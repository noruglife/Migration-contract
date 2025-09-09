# NoRug Protocol

![NoRug Protocol Logo](https://i.ibb.co/3YTfWhnD/88-C26570-A90-B-4073-B87-D-0396-FDE0-C195.png)

## Overview
The NoRug Protocol is a decentralized platform on Solana that protects users from rug pulls, particularly for tokens launched on Pump.fun. It offers insurance policies, staking rewards, community-governed lotteries, and token buybacks, with advanced rug pull risk analysis powered by on-chain metrics and oracles. The protocol incentivizes participation through $NORUG token rewards and ensures fairness via decentralized governance.

**Key Features**:
- **Insurance**: Purchase coverage for tokens with $NORUG premiums, distributed across insurance, staking, lottery, and buyback pools.
- **Rug Pull Checker**: Analyzes Pump.fun tokens for risks (holder concentration, liquidity, developer history).
- **Staking**: Stake $NORUG to earn proportional rewards from the staking pool.
- **Lottery**: Participate in fair lotteries with multiple prize tiers, using Chainlink VRF for randomness.
- **Governance**: Vote on claims, lotteries, and protocol upgrades via a DAO-like system.
- **Buyback and Burn**: Repurchase and burn $NORUG tokens to stabilize value.
- **Oracles**: Pyth for price feeds, Chainlink VRF for lotteries, and a custom risk oracle for token analysis.

**License**: SPDX-License-Identifier: MIT  
**Copyright**: 2025 NoRug Protocol, [https://www.norug.life/](https://www.norug.life/)

## Architecture
The protocol is built with the Anchor framework on Solana, ensuring modularity, security, and scalability. Key components include:

- **Protocol Account**: Stores global state (pools, mints, percentages, $NORUG price).
- **InsurancePolicy Account**: Tracks user policies (token insured, coverage, premium).
- **StakingAccount**: Manages staked $NORUG and reward claims.
- **VoteProposal Account**: Handles governance proposals (claims, lotteries, parameter updates).
- **RugPullRiskReport**: Returns risk analysis for Pump.fun tokens (holder concentration, liquidity, developer history).
- **Oracles**:
  - **Pyth**: Provides $NORUG/USDC price feeds.
  - **Chainlink VRF**: Ensures fair lottery winner selection.
  - **Custom Risk Oracle**: Evaluates token risk based on on-chain metrics.

### Workflow Diagram
Below is a Mermaid graph illustrating the NoRug Protocol workflow, showing interactions between users, the protocol, and oracles.

```mermaid
graph TD
    A[User] -->|Buy Insurance| B(Protocol)
    A -->|Stake $NORUG| B
    A -->|Propose Lottery| B
    A -->|File Claim| B
    A -->|Analyze Token| B
    B -->|Fetch Price| C[Pyth Oracle]
    B -->|Fetch Randomness| D[Chainlink VRF]
    B -->|Fetch Risk Score| E[Risk Oracle]
    B -->|Distribute Premium| F[Insurance Pool]
    B -->|Distribute Premium| G[Staking Pool]
    B -->|Distribute Premium| H[Lottery Pool]
    B -->|Distribute Premium| I[Buyback Reserve]
    B -->|Claim Rewards| A
    B -->|Execute Lottery| A
    B -->|Buyback and Burn| J[Burn Account]
    B -->|Vote on Proposals| K[Governance]
    K -->|Approve Claims| A
