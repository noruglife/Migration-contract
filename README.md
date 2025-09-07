# 🛡️ NoRug Protocol

## Overview
**NoRug Protocol** is a Solana program that protects token investors from rug pulls while rewarding long-term holders.  

It provides:
- **Token migration** from legacy [pump.fun](https://pump.fun) tokens into the new `$NORUG` token.  
- **Insurance pool** that pays out when tokens rug.  
- **Staking & rewards** for token holders.  
- **Lottery system** funded from insurance premiums.  
- **Buyback & burn** mechanism to support token value.  

This repository contains the **Anchor program** for the protocol.

---

## 🔑 Key Features
- **Migration**:  
  - Users can swap old pump.fun tokens → `$NORUG` tokens.  
  - Legacy tokens are transferred into a **PDA-owned burn vault** where they are permanently quarantined (cannot be withdrawn).  
  - New tokens are distributed from a migration vault at a 1:1 ratio.  
  - Early birds (first 48 hours) get a **+10% bonus**.  

- **Insurance**:  
  - Users can buy policies in `$NORUG` to cover other tokens.  
  - Premiums are split into pools: insurance, staking, lottery, and buyback.  

- **Staking**:  
  - Users stake `$NORUG` and earn rewards from protocol revenue.  

- **Claims**:  
  - When a token rugs, insured users can submit claims.  
  - Claims are automatically verified (for pump.fun tokens) and can be paid out from the insurance pool.  

- **Lottery**:  
  - 20% of all insurance premiums are allocated to the lottery pool.  
  - These funds will later be distributed via raffles to participants.  

- **Buybacks**:  
  - The protocol periodically uses reserves to buy back and burn `$NORUG`, reducing supply.  

---
## 📊 Protocol Workflow

Below is a flowchart illustrating how the NoRug Protocol operates, including token migration, insurance, staking, claims, lottery, and buyback mechanisms.

```mermaid
graph TD
    A[User with pump.fun Tokens] -->|Swap Tokens| B[Migration Process]
    B -->|1:1 Ratio + 10pct Bonus First 48h| C[$NORUG Tokens]
    B -->|Legacy Tokens| D[PDA Burn Vault]
    
    C -->|Buy Insurance| E[Insurance Pool]
    E -->|Premiums Split| F[Staking Pool]
    E -->|Premiums Split| G[Lottery Pool]
    E -->|Premiums Split| H[Buyback Pool]
    
    C -->|Stake $NORUG| F
    F -->|Earn Rewards| I[User Rewards]
    
    J[Token Rugs] -->|Submit Claim| K[Claims Verification]
    K -->|Verified for pump.fun Tokens| L[Payout from Insurance Pool]
    L -->|Receive $NORUG| I
    
    G -->|20pct Premiums| M[Lottery Raffles]
    M -->|Win Prizes| I
    
    H -->|Periodic Buyback| N[Buyback & Burn]
    N -->|Reduce $NORUG Supply| O[Increased Token Value]
