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

