# NoRug Protocol Whitepaper

**Version 1.0**  
**Date: September 8, 2025**  
**License: SPDX-License-Identifier: MIT**  
**Copyright © 2025 NoRug Protocol**  
**Website: https://www.norug.life/**  

---

## Abstract

The NoRug Protocol is a decentralized platform built on the Solana blockchain, designed to protect users from rug pulls—scams where developers abandon projects or drain liquidity, leaving investors with worthless tokens. Focused on tokens launched via Pump.fun, the protocol offers advanced rug pull risk analysis, insurance policies, staking rewards, community-governed lotteries, and token buybacks. Powered by the $NORUG token, it incentivizes participation through rewards and ensures fairness via decentralized governance and trusted oracles (Pyth, Chainlink VRF). This whitepaper outlines the protocol’s vision, features, architecture, economic model, and the migration strategy for transitioning the Pump.fun token RUGME to $NORUG via a 1:1 swap or airdrop.

---

## 1. Introduction

### 1.1 Background

Decentralized finance (DeFi) has revolutionized financial systems by enabling trustless, permissionless transactions. Platforms like Pump.fun have lowered barriers to token creation on Solana, fostering innovation but also enabling rug pulls, where malicious developers drain liquidity or abandon projects, causing significant losses. The NoRug Protocol addresses this by offering tools to analyze, mitigate, and insure against rug pull risks, creating a safer DeFi ecosystem.

### 1.2 Problem Statement: The Rug Pull Epidemic on Pump.fun

Pump.fun’s user-friendly interface has made it a popular platform for token launches, but it has also become a hotspot for rug pulls. Many tokens exhibit red flags such as high holder concentration, sudden liquidity withdrawals, or dubious developer histories. On-chain analytics suggest a significant percentage of Pump.fun tokens are at risk, eroding trust in DeFi. The NoRug Protocol counters this epidemic with advanced risk analysis, insurance, and governance, restoring confidence in token launches.

### 1.3 RUGME to $NORUG Migration

To align with the NoRug Protocol’s mission, the Pump.fun token **RUGME** will transition to the $NORUG token, the native currency of the protocol. All RUGME holders will receive $NORUG tokens on a **1:1 basis** through a token swap or airdrop. The migration process will occur over a **7-day period** (`MIGRATION_DURATION`), with a **2-day bonus window** offering a **10% bonus** in $NORUG tokens for early participants (`BONUS_WINDOW`, `BONUS_MULTIPLIER: 110`). This ensures a seamless transition, incentivizes participation, and aligns RUGME holders with the protocol’s protective features and governance model.

### 1.4 Vision

The NoRug Protocol aims to empower DeFi investors by mitigating rug pull risks, fostering trust in token launches, and promoting sustainability. By leveraging Solana’s high-throughput blockchain and advanced analytics, it ensures transparency, security, and fairness.

### 1.5 Objectives

- Protect investors from rug pulls through comprehensive token risk analysis.
- Provide insurance coverage for Pump.fun and other Solana tokens.
- Facilitate a smooth 1:1 migration from RUGME to $NORUG.
- Incentivize participation through $NORUG rewards, staking, and lotteries.
- Enable decentralized governance for community-driven decisions.
- Stabilize $NORUG value via buyback and burn mechanisms.

---

## 2. Key Features

### 2.1 Rug Pull Checker

The **Rug Pull Checker** analyzes Pump.fun tokens for rug pull risks, evaluating:

- **Holder Concentration**: Detects if a small group holds most tokens (e.g., >40% by top 10 wallets indicates higher risk).
- **Liquidity Monitoring**: Tracks pool activity for sudden withdrawals (e.g., liquidity <1,000 USDC flags risk).
- **Developer History**: Assesses creators’ past tokens and rug pull records.

Using a **Custom Risk Oracle**, it assigns a risk score (0–100), with thresholds: Low (0–30), Medium (31–60), High (61–80), Very High (81–100). Tokens scoring ≥90 are blocked from insurance coverage.

### 2.2 Insurance Policies

Users can insure Pump.fun tokens against rug pulls by paying $NORUG premiums. Key details:

- **Premiums**: Calculated based on coverage amount (minimum 1 USDC), duration (up to 90 days), and risk score.
- **Pools**: Premiums are split across insurance (claims), staking (rewards), lottery (prizes), and buyback pools (percentages set by governance, summing to 100%).
- **Claims**: Verified via governance votes and rug pull status checks (e.g., liquidity removal >90%).

### 2.3 Staking

Users stake $NORUG (minimum 100 tokens) to earn rewards from the staking pool, distributed proportionally. Rewards are claimable hourly, with a 7-day lockup period.

### 2.4 Community-Governed Lotteries

Lotteries offer multiple prize tiers (e.g., 50% for 1st, 25% for 2nd and 3rd), funded by premiums. **Chainlink VRF** ensures fair winner selection, with governance votes approving distributions.

### 2.5 Decentralized Governance

$NORUG holders (minimum 10 tokens for voting) govern the protocol, voting on claims, lotteries, and parameter changes (e.g., pool percentages) over a 3-day voting period.

### 2.6 Buyback and Burn

Premiums fund $NORUG repurchasing, which is burned to reduce the 1 billion token supply, stabilizing value.

### 2.7 Oracles

- **Pyth**: Provides $NORUG/USDC price feeds for accurate pricing.
- **Chainlink VRF**: Ensures fair lottery randomness.
- **Custom Risk Oracle**: Aggregates on-chain metrics for risk scores.

---

## 3. Technical Architecture

Built with the **Anchor framework** on Solana, the protocol ensures modularity, security, and scalability.

### 3.1 Protocol Account

Stores global state:
- Pool balances (insurance, staking, lottery, buyback).
- $NORUG mint and price.
- Total supply: 1,000,000,000 $NORUG (9 decimals).
- Governance parameters (e.g., pool percentages).

### 3.2 InsurancePolicy Account

Tracks user policies:
- Insured token, coverage amount (minimum 1 USDC), premium.
- Duration (up to 90 days), active status, claim history.

### 3.3 StakingAccount

Manages:
- Staked $NORUG (minimum 100 tokens).
- Reward claims (hourly, post-lockup).

### 3.4 VoteProposal Account

Handles governance proposals:
- Claims, lotteries, parameter updates.
- Voting period: 3 days.

### 3.5 RugPullRiskReport

Outputs risk analysis:
- Risk score, holder concentration, liquidity status, developer history.
- Risk levels: Low, Medium, High, Very High.

### 3.6 Oracles

- **Pyth**: Real-time $NORUG/USDC pricing.
- **Chainlink VRF**: Randomness for lotteries.
- **Custom Risk Oracle**: On-chain risk metrics.

---

## 4. Economic Model

### 4.1 $NORUG Token

The $NORUG token (1 billion total supply, 9 decimals) is used for:
- Paying insurance premiums.
- Staking (minimum 100 $NORUG).
- Voting (minimum 10 $NORUG).
- Lottery participation (minimum 1 $NORUG premium).

### 4.2 RUGME Migration

RUGME holders will receive $NORUG tokens on a 1:1 basis via:
- **Token Swap**: Exchange RUGME for $NORUG during a 7-day migration period.
- **Airdrop**: $NORUG distributed to RUGME holders’ wallets.
- **Bonus Incentive**: 10% additional $NORUG for swaps within the first 2 days.
The migration ensures RUGME holders seamlessly transition to the NoRug ecosystem.

### 4.3 Token Distribution

Premiums are allocated
