// SPDX-License-Identifier: MIT
// Copyright 2025 NoRug Protocol, https://www.norug.life/

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};
use pyth_sdk_solana::state::PriceAccount;
use chainlink_solana as chainlink;

declare_id!("NoRug11111111111111111111111111111111111111");

/// Constants defining protocol parameters
const DAY_SECONDS: i64 = 86_400;
const MIGRATION_DURATION: i64 = 7 * DAY_SECONDS;
const BONUS_WINDOW: i64 = 2 * DAY_SECONDS;
const STAKING_LOCKUP: i64 = 7 * DAY_SECONDS;
const VOTING_PERIOD: i64 = 3 * DAY_SECONDS;
const LOTTERY_PROPOSAL_COOLDOWN: i64 = DAY_SECONDS;
const MIN_CLAIM_INTERVAL: i64 = 3600; // 1 hour
const TOTAL_SUPPLY: u64 = 1_000_000_000 * 10u64.pow(9); // 1B tokens, 9 decimals
const MIN_COVERAGE: u64 = 1_000_000; // 1 USDC
const MIN_STAKE: u64 = 100 * 10u64.pow(9); // 100 $NORUG
const MIN_VOTE_STAKE: u64 = 10 * 10u64.pow(9); // 10 $NORUG
const MIN_LOTTERY_PRIZE: u64 = 100 * 10u64.pow(9); // 100 $NORUG
const MIN_LOTTERY_PREMIUM: u64 = 1 * 10u64.pow(9); // 1 $NORUG
const BONUS_MULTIPLIER: u64 = 110; // 10% bonus
const MAX_COVERAGE_DAYS: u64 = 90;

/// Error codes for robust error handling
#[error_code]
pub enum ErrorCode {
    #[msg("Insufficient funds in user account")]
    InsufficientFunds,
    #[msg("Insufficient vault funds")]
    InsufficientVaultFunds,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("Arithmetic underflow")]
    Underflow,
    #[msg("Invalid owner")]
    InvalidOwner,
    #[msg("Invalid token mint")]
    InvalidToken,
    #[msg("Invalid duration")]
    InvalidDuration,
    #[msg("Policy is inactive")]
    PolicyInactive,
    #[msg("Policy already claimed")]
    AlreadyClaimed,
    #[msg("Policy expired")]
    PolicyExpired,
    #[msg("Invalid pool percentages")]
    InvalidPoolPercentages,
    #[msg("No eligible participants")]
    NoEligibleParticipants,
    #[msg("Minimum stake not met")]
    MinimumStake,
    #[msg("Vote is not active")]
    VoteNotActive,
    #[msg("Vote period has not ended")]
    VoteNotEnded,
    #[msg("Vote not approved")]
    VoteNotApproved,
    #[msg("Invalid price")]
    InvalidPrice,
    #[msg("Invalid price exponent")]
    InvalidPriceExponent,
    #[msg("Stale price")]
    StalePrice,
    #[msg("Invalid VRF result")]
    InvalidVRFResult,
    #[msg("Invalid risk score")]
    InvalidRiskScore,
    #[msg("Token not rugged")]
    NotRugged,
    #[msg("Invalid page")]
    InvalidPage,
    #[msg("Too early to claim rewards")]
    TooEarly,
    #[msg("No rewards available")]
    NoRewards,
    #[msg("High rug pull risk")]
    HighRugRisk,
}

/// Main program
#[program]
pub mod norug_protocol {
    use super::*;

    /// Initialize the protocol
    pub fn initialize(
        ctx: Context<Initialize>,
        insurance_pool_pct: u8,
        staking_pool_pct: u8,
        lottery_pool_pct: u8,
        buyback_pool_pct: u8,
        rugme_price: u64,
    ) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        require!(
            insurance_pool_pct + staking_pool_pct + lottery_pool_pct + buyback_pool_pct == 100,
            ErrorCode::InvalidPoolPercentages
        );
        require_gt!(rugme_price, 0, ErrorCode::InvalidPrice);

        protocol.authority = ctx.accounts.authority.key();
        protocol.rugme_mint = ctx.accounts.rugme_mint.key();
        protocol.usdc_mint = ctx.accounts.usdc_mint.key();
        protocol.total_supply = TOTAL_SUPPLY;
        protocol.insurance_pool = 0;
        protocol.staking_pool = 0;
        protocol.lottery_pool = 0;
        protocol.buyback_reserve = 0;
        protocol.total_staked = 0;
        protocol.total_policies = 0;
        protocol.total_votes = 0;
        protocol.total_premiums = 0;
        protocol.protocol_bump = *ctx.bumps.get("protocol").unwrap();
        protocol.insurance_pool_pct = insurance_pool_pct;
        protocol.staking_pool_pct = staking_pool_pct;
        protocol.lottery_pool_pct = lottery_pool_pct;
        protocol.buyback_pool_pct = buyback_pool_pct;
        protocol.rugme_price = rugme_price;
        protocol.last_proposal_time = 0;

        emit!(ProtocolInitialized {
            authority: protocol.authority,
            rugme_mint: protocol.rugme_mint,
            usdc_mint: protocol.usdc_mint,
            insurance_pool_pct,
            staking_pool_pct,
            lottery_pool_pct,
            buyback_pool_pct,
            rugme_price,
        });
        Ok(())
    }

    /// Update pool percentages (governance only)
    pub fn update_pool_percentages(
        ctx: Context<UpdatePoolPercentages>,
        insurance_pool_pct: u8,
        staking_pool_pct: u8,
        lottery_pool_pct: u8,
        buyback_pool_pct: u8,
    ) -> Result<()> {
        require!(
            insurance_pool_pct + staking_pool_pct + lottery_pool_pct + buyback_pool_pct == 100,
            ErrorCode::InvalidPoolPercentages
        );
        let protocol = &mut ctx.accounts.protocol;
        protocol.insurance_pool_pct = insurance_pool_pct;
        protocol.staking_pool_pct = staking_pool_pct;
        protocol.lottery_pool_pct = lottery_pool_pct;
        protocol.buyback_pool_pct = buyback_pool_pct;

        emit!(PoolPercentagesUpdated {
            insurance_pool_pct,
            staking_pool_pct,
            lottery_pool_pct,
            buyback_pool_pct,
        });
        Ok(())
    }

    /// Update $NORUG price using Pyth oracle
    pub fn update_rugme_price(ctx: Context<UpdateRugmePrice>, price: u64) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let pyth_price_account = &ctx.accounts.pyth_price_account;

        // Validate Pyth price
        let price_data = PriceAccount::try_from_slice(&pyth_price_account.data.borrow())?;
        require!(price_data.price > 0, ErrorCode::InvalidPrice);
        require!(price_data.expo == -9, ErrorCode::InvalidPriceExponent);
        require!(
            price_data.publish_time >= Clock::get()?.unix_timestamp - 60,
            ErrorCode::StalePrice
        );

        protocol.rugme_price = price_data.price as u64;
        emit!(PriceUpdated {
            new_price: protocol.rugme_price,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Buy insurance for a token
    pub fn buy_insurance(
        ctx: Context<BuyInsurance>,
        token_to_insure: Pubkey,
        coverage_amount: u64,
        coverage_days: u64,
    ) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let user = &ctx.accounts.user;
        let user_rugme = &ctx.accounts.user_rugme;
        let protocol_vault = &ctx.accounts.protocol_vault;
        let policy = &mut ctx.accounts.policy;
        let user_premiums = &mut ctx.accounts.user_premiums;
        let premium_payer = &mut ctx.accounts.premium_payer;

        // Validate inputs
        require_gt!(coverage_days, 0, ErrorCode::InvalidDuration);
        require!(
            coverage_days <= MAX_COVERAGE_DAYS,
            ErrorCode::InvalidDuration
        );
        require_gte!(coverage_amount, MIN_COVERAGE, ErrorCode::InsufficientFunds);
        require!(
            ctx.accounts.token_mint.key() != Pubkey::default(),
            ErrorCode::InvalidToken
        );

        // Check rug pull risk
        let risk_score = fetch_risk_score(&token_to_insure)?;
        require!(risk_score < 90, ErrorCode::HighRugRisk); // Block high-risk tokens

        // Calculate premium
        let premium_usdc = calculate_premium_usdc(coverage_amount, coverage_days, risk_score)?;
        let premium_rugme = premium_usdc
            .checked_mul(10u64.pow(9))
            .ok_or(ErrorCode::Overflow)?
            .checked_div(protocol.rugme_price)
            .ok_or(ErrorCode::Underflow)?;

        // Validate funds
        require_gte!(
            user_rugme.amount,
            premium_rugme,
            ErrorCode::InsufficientFunds
        );

        // Transfer premium
        let cpi_accounts = Transfer {
            from: user_rugme.to_account_info(),
            to: protocol_vault.to_account_info(),
            authority: user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        token::transfer(CpiContext::new(cpi_program, cpi_accounts), premium_rugme)?;

        // Distribute premium
        let insurance_share = premium_rugme
            .checked_mul(protocol.insurance_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let staking_share = premium_rugme
            .checked_mul(protocol.staking_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let lottery_share = premium_rugme
            .checked_mul(protocol.lottery_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let buyback_share = premium_rugme
            .checked_mul(protocol.buyback_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;

        protocol.insurance_pool = protocol
            .insurance_pool
            .checked_add(insurance_share)
            .ok_or(ErrorCode::Overflow)?;
        protocol.staking_pool = protocol
            .staking_pool
            .checked_add(staking_share)
            .ok_or(ErrorCode::Overflow)?;
        protocol.lottery_pool = protocol
            .lottery_pool
            .checked_add(lottery_share)
            .ok_or(ErrorCode::Overflow)?;
        protocol.buyback_reserve = protocol
            .buyback_reserve
            .checked_add(buyback_share)
            .ok_or(ErrorCode::Overflow)?;
        protocol.total_premiums = protocol
            .total_premiums
            .checked_add(premium_rugme)
            .ok_or(ErrorCode::Overflow)?;

        // Update policy
        policy.owner = user.key();
        policy.token_insured = token_to_insure;
        policy.coverage_amount = coverage_amount;
        policy.premium_amount = premium_rugme;
        policy.start_time = Clock::get()?.unix_timestamp;
        policy.end_time = policy.start_time + (coverage_days as i64 * DAY_SECONDS);
        policy.is_active = true;
        policy.has_claimed = false;
        policy.policy_id = protocol.total_policies;

        // Update user premiums
        user_premiums.user = user.key();
        user_premiums.total_premium = user_premiums
            .total_premium
            .checked_add(premium_rugme)
            .ok_or(ErrorCode::Overflow)?;
        premium_payer.user = user.key();
        premium_payer.premium_amount = user_premiums.total_premium;

        protocol.total_policies = protocol
            .total_policies
            .checked_add(1)
            .ok_or(ErrorCode::Overflow)?;

        emit!(PolicyCreated {
            policy_id: policy.policy_id,
            owner: policy.owner,
            token_insured: policy.token_insured,
            coverage_amount,
            premium_amount: premium_rugme,
            start_time: policy.start_time,
            end_time: policy.end_time,
        });
        Ok(())
    }

    /// Cancel an insurance policy
    pub fn cancel_insurance(ctx: Context<CancelInsurance>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let policy = &mut ctx.accounts.policy;
        let user_premiums = &mut ctx.accounts.user_premiums;
        let premium_payer = &mut ctx.accounts.premium_payer;
        let protocol_vault = &ctx.accounts.protocol_vault;
        let user_rugme = &ctx.accounts.user_rugme;

        require!(policy.is_active, ErrorCode::PolicyInactive);
        require!(!policy.has_claimed, ErrorCode::AlreadyClaimed);
        require_eq!(
            policy.owner,
            ctx.accounts.user.key(),
            ErrorCode::InvalidOwner
        );

        let current_time = Clock::get()?.unix_timestamp;
        let elapsed_days = (current_time - policy.start_time) / DAY_SECONDS;
        let total_days = (policy.end_time - policy.start_time) / DAY_SECONDS;
        let refund_ratio = if elapsed_days <= 1 {
            100
        } else {
            ((total_days - elapsed_days) * 100 / total_days) as u64
        };
        let refund = policy
            .premium_amount
            .checked_mul(refund_ratio)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;

        require_gte!(
            protocol.insurance_pool,
            refund,
            ErrorCode::InsufficientVaultFunds
        );

        // Reverse pool contributions
        let insurance_share = refund
            .checked_mul(protocol.insurance_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let staking_share = refund
            .checked_mul(protocol.staking_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let lottery_share = refund
            .checked_mul(protocol.lottery_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;
        let buyback_share = refund
            .checked_mul(protocol.buyback_pool_pct as u64)
            .ok_or(ErrorCode::Overflow)?
            .checked_div(100)
            .ok_or(ErrorCode::Underflow)?;

        protocol.insurance_pool = protocol
            .insurance_pool
            .checked_sub(insurance_share)
            .ok_or(ErrorCode::Underflow)?;
        protocol.staking_pool = protocol
            .staking_pool
            .checked_sub(staking_share)
            .ok_or(ErrorCode::Underflow)?;
        protocol.lottery_pool = protocol
            .lottery_pool
            .checked_sub(lottery_share)
            .ok_or(ErrorCode::Underflow)?;
        protocol.buyback_reserve = protocol
            .buyback_reserve
            .checked_sub(buyback_share)
            .ok_or(ErrorCode::Underflow)?;
        user_premiums.total_premium = user_premiums
            .total_premium
            .checked_sub(refund)
            .ok_or(ErrorCode::Underflow)?;
        premium_payer.premium_amount = user_premiums.total_premium;

        // Transfer refund
        let seeds = &[b"protocol".as_ref(), &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: protocol_vault.to_account_info(),
            to: user_rugme.to_account_info(),
            authority: protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        token::transfer(CpiContext::new_with_signer(cpi_program, cpi_accounts, signer), refund)?;

        policy.is_active = false;
        emit!(PolicyCanceled {
            policy_id: policy.policy_id,
            owner: policy.owner,
            refund_amount: refund,
        });
        Ok(())
    }

    /// File a claim for a rugged token
    pub fn file_claim(ctx: Context<FileClaim>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let policy = &ctx.accounts.policy;
        let vote_proposal = &mut ctx.accounts.vote_proposal;
        let current_time = Clock::get()?.unix_timestamp;

        require!(policy.is_active, ErrorCode::PolicyInactive);
        require!(!policy.has_claimed, ErrorCode::AlreadyClaimed);
        require!(
            current_time < policy.end_time,
            ErrorCode::PolicyExpired
        );
        require_eq!(
            policy.owner,
            ctx.accounts.user.key(),
            ErrorCode::InvalidOwner
        );

        // Verify rug pull
        let is_rugged = fetch_rug_pull_status(&policy.token_insured)?;
        require!(is_rugged, ErrorCode::NotRugged);

        vote_proposal.vote_id = protocol.total_votes;
        vote_proposal.proposer = ctx.accounts.user.key();
        vote_proposal.vote_type = VoteType::ClaimApproval;
        vote_proposal.target = policy.owner;
        vote_proposal.amount = policy.coverage_amount;
        vote_proposal.yes_votes = 0;
        vote_proposal.no_votes = 0;
        vote_proposal.start_time = current_time;
        vote_proposal.end_time = current_time + VOTING_PERIOD;
        vote_proposal.is_active = true;

        protocol.total_votes = protocol
            .total_votes
            .checked_add(1)
            .ok_or(ErrorCode::Overflow)?;

        emit!(ClaimProposed {
            policy_id: policy.policy_id,
            owner: policy.owner,
            coverage: policy.coverage_amount,
        });
        Ok(())
    }

    /// Propose a lottery with multiple prize tiers
    pub fn propose_lottery(ctx: Context<ProposeLottery>, vrf_request_id: u64) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let vote_proposal = &mut ctx.accounts.vote_proposal;
        let staking_account = &ctx.accounts.staking_account;
        let current_time = Clock::get()?.unix_timestamp;

        require!(
            current_time >= protocol.last_proposal_time + LOTTERY_PROPOSAL_COOLDOWN,
            ErrorCode::TooEarly
        );
        require_gte!(
            staking_account.amount,
            MIN_VOTE_STAKE,
            ErrorCode::MinimumStake
        );
        require_gte!(
            protocol.lottery_pool,
            MIN_LOTTERY_PRIZE,
            ErrorCode::InsufficientVaultFunds
        );
        require!(
            !ctx.accounts.premium_payers.is_empty(),
            ErrorCode::NoEligibleParticipants
        );

        let prize_amounts = [
            protocol.lottery_pool / 2, // 1st: 50%
            protocol.lottery_pool / 4, // 2nd: 25%
            protocol.lottery_pool / 4, // 3rd: 25%
        ];
        let winners = [
            fetch_vrf_winner(
                &ctx.accounts.vrf_account,
                vrf_request_id,
                &ctx.accounts.premium_payers,
                0,
                100,
            )?,
            fetch_vrf_winner(
                &ctx.accounts.vrf_account,
                vrf_request_id + 1,
                &ctx.accounts.premium_payers,
                0,
                100,
            )?,
            fetch_vrf_winner(
                &ctx.accounts.vrf_account,
                vrf_request_id + 2,
                &ctx.accounts.premium_payers,
                0,
                100,
            )?,
        ];

        vote_proposal.vote_id = protocol.total_votes;
        vote_proposal.proposer = ctx.accounts.user.key();
        vote_proposal.vote_type = VoteType::Lottery;
        vote_proposal.target = winners[0]; // Store first winner; others handled off-chain
        vote_proposal.amount = prize_amounts[0]; // First prize
        vote_proposal.yes_votes = 0;
        vote_proposal.no_votes = 0;
        vote_proposal.start_time = current_time;
        vote_proposal.end_time = current_time + VOTING_PERIOD;
        vote_proposal.is_active = true;

        protocol.lottery_pool = 0;
        protocol.total_votes = protocol
            .total_votes
            .checked_add(1)
            .ok_or(ErrorCode::Overflow)?;
        protocol.last_proposal_time = current_time;

        emit!(LotteryProposed {
            winners,
            amounts: prize_amounts,
        });
        Ok(())
    }

    /// Execute a lottery
    pub fn execute_lottery(ctx: Context<ExecuteLottery>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let vote_proposal = &ctx.accounts.vote_proposal;
        let winner_rugme = &ctx.accounts.winner_rugme;
        let protocol_vault = &ctx.accounts.protocol_vault;
        let current_time = Clock::get()?.unix_timestamp;

        require!(vote_proposal.is_active, ErrorCode::VoteNotActive);
        require!(
            current_time >= vote_proposal.end_time,
            ErrorCode::VoteNotEnded
        );
        require!(
            vote_proposal.yes_votes > vote_proposal.no_votes,
            ErrorCode::VoteNotApproved
        );

        let seeds = &[b"protocol".as_ref(), &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: protocol_vault.to_account_info(),
            to: winner_rugme.to_account_info(),
            authority: protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        token::transfer(
            CpiContext::new_with_signer(cpi_program, cpi_accounts, signer),
            vote_proposal.amount,
        )?;

        vote_proposal.is_active = false;
        emit!(LotteryWon {
            winner: vote_proposal.target,
            amount: vote_proposal.amount,
        });
        Ok(())
    }

    /// Claim staking rewards
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let staking_account = &ctx.accounts.staking_account;
        let protocol_vault = &ctx.accounts.protocol_vault;
        let user_rugme = &ctx.accounts.user_rugme;
        let current_time = Clock::get()?.unix_timestamp;

        require_gte!(
            staking_account.amount,
            MIN_STAKE,
            ErrorCode::MinimumStake
        );
        require!(
            current_time >= staking_account.last_claim + MIN_CLAIM_INTERVAL,
            ErrorCode::TooEarly
        );

        let reward = calculate_staking_reward(staking_account, protocol)?;
        require_gte!(
            protocol.staking_pool,
            reward,
            ErrorCode::NoRewards
        );

        let seeds = &[b"protocol".as_ref(), &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: protocol_vault.to_account_info(),
            to: user_rugme.to_account_info(),
            authority: protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        token::transfer(CpiContext::new_with_signer(cpi_program, cpi_accounts, signer), reward)?;

        protocol.staking_pool = protocol
            .staking_pool
            .checked_sub(reward)
            .ok_or(ErrorCode::Underflow)?;
        staking_account.last_claim = current_time;

        emit!(RewardsClaimed {
            user: ctx.accounts.user.key(),
            amount: reward,
        });
        Ok(())
    }

    /// Execute buyback and burn
    pub fn buyback(ctx: Context<Buyback>, amount: u64) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let protocol_vault = &ctx.accounts.protocol_vault;
        let burn_account = &ctx.accounts.burn_account;

        require_gte!(
            protocol.buyback_reserve,
            amount,
            ErrorCode::InsufficientVaultFunds
        );

        let seeds = &[b"protocol".as_ref(), &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: protocol_vault.to_account_info(),
            to: burn_account.to_account_info(),
            authority: protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        token::transfer(CpiContext::new_with_signer(cpi_program, cpi_accounts, signer), amount)?;

        protocol.buyback_reserve = protocol
            .buyback_reserve
            .checked_sub(amount)
            .ok_or(ErrorCode::Underflow)?;

        emit!(BuybackExecuted {
            amount,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    /// Analyze a Pump.fun token for rug pull risk
    pub fn analyze_token(ctx: Context<AnalyzeToken>, token: Pubkey) -> Result<RugPullRiskReport> {
        let protocol = &ctx.accounts.protocol;

        // Fetch risk metrics
        let risk_score = fetch_risk_score(&token)?;
        let holder_concentration = fetch_holder_concentration(&token)?;
        let liquidity_status = fetch_liquidity_status(&token)?;
        let dev_history = fetch_dev_history(&token)?;

        let report = RugPullRiskReport {
            token,
            risk_score,
            holder_concentration,
            liquidity_locked: liquidity_status.locked,
            liquidity_amount: liquidity_status.amount,
            dev_previous_rugs: dev_history.previous_rugs,
            dev_token_count: dev_history.token_count,
            risk_level: match risk_score {
                0..=30 => RiskLevel::Low,
                31..=60 => RiskLevel::Medium,
                61..=80 => RiskLevel::High,
                _ => RiskLevel::VeryHigh,
            },
        };

        emit!(TokenAnalyzed {
            token,
            risk_score,
            risk_level: report.risk_level,
        });
        Ok(report)
    }
}

/// Accounts structs
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(init, payer = authority, space = Protocol::LEN, seeds = [b"protocol"], bump)]
    pub protocol: Account<'info, Protocol>,
    pub rugme_mint: Account<'info, Mint>,
    pub usdc_mint: Account<'info, Mint>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct UpdatePoolPercentages<'info> {
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(signer, constraint = protocol.authority == authority.key() @ ErrorCode::InvalidOwner)]
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct UpdateRugmePrice<'info> {
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    pub pyth_price_account: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct BuyInsurance<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(mut, constraint = user_rugme.mint == protocol.rugme_mint)]
    pub user_rugme: Account<'info, TokenAccount>,
    #[account(
        mut,
        seeds = [b"protocol_vault"],
        bump,
        constraint = protocol_vault.owner == protocol.key() @ ErrorCode::InvalidOwner
    )]
    pub protocol_vault: Account<'info, TokenAccount>,
    #[account(
        init,
        payer = user,
        space = InsurancePolicy::LEN,
        seeds = [b"policy", protocol.total_policies.to_le_bytes().as_ref()],
        bump
    )]
    pub policy: Account<'info, InsurancePolicy>,
    #[account(
        init_if_needed,
        payer = user,
        space = UserPremiums::LEN,
        seeds = [b"premiums", user.key().as_ref()],
        bump
    )]
    pub user_premiums: Account<'info, UserPremiums>,
    #[account(
        init_if_needed,
        payer = user,
        space = PremiumPayer::LEN,
        seeds = [b"payer", user.key().as_ref()],
        bump
    )]
    pub premium_payer: Account<'info, PremiumPayer>,
    pub token_mint: Account<'info, Mint>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct CancelInsurance<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(
        mut,
        close = user,
        seeds = [b"policy", policy.policy_id.to_le_bytes().as_ref()],
        bump
    )]
    pub policy: Account<'info, InsurancePolicy>,
    #[account(
        mut,
        seeds = [b"premiums", user.key().as_ref()],
        bump
    )]
    pub user_premiums: Account<'info, UserPremiums>,
    #[account(
        mut,
        seeds = [b"payer", user.key().as_ref()],
        bump
    )]
    pub premium_payer: Account<'info, PremiumPayer>,
    #[account(
        mut,
        seeds = [b"protocol_vault"],
        bump,
        constraint = protocol_vault.owner == protocol.key() @ ErrorCode::InvalidOwner
    )]
    pub protocol_vault: Account<'info, TokenAccount>,
    #[account(mut)]
    pub user_rugme: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct FileClaim<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(mut)]
    pub policy: Account<'info, InsurancePolicy>,
    #[account(
        init,
        payer = user,
        space = VoteProposal::LEN,
        seeds = [b"claim_vote", protocol.total_votes.to_le_bytes().as_ref()],
        bump
    )]
    pub vote_proposal: Account<'info, VoteProposal>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
#[instruction(vrf_request_id: u64)]
pub struct ProposeLottery<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(
        mut,
        constraint = staking_account.owner == user.key() @ ErrorCode::InvalidOwner
    )]
    pub staking_account: Account<'info, StakingAccount>,
    #[account(
        init,
        payer = user,
        space = VoteProposal::LEN,
        seeds = [b"vote", protocol.total_votes.to_le_bytes().as_ref()],
        bump
    )]
    pub vote_proposal: Account<'info, VoteProposal>,
    /// CHECK: VRF account validated by Chainlink
    pub vrf_account: AccountInfo<'info>,
    #[account(
        constraint = premium_payers.iter().all(|p| p.premium_amount >= MIN_LOTTERY_PREMIUM)
    )]
    pub premium_payers: Vec<Account<'info, PremiumPayer>>,
    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct ExecuteLottery<'info> {
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(
        mut,
        close = user,
        seeds = [b"vote", vote_proposal.vote_id.to_le_bytes().as_ref()],
        bump
    )]
    pub vote_proposal: Account<'info, VoteProposal>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub winner_rugme: Account<'info, TokenAccount>,
    #[account(
        mut,
        seeds = [b"protocol_vault"],
        bump,
        constraint = protocol_vault.owner == protocol.key() @ ErrorCode::InvalidOwner
    )]
    pub protocol_vault: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(
        mut,
        constraint = staking_account.owner == user.key() @ ErrorCode::InvalidOwner
    )]
    pub staking_account: Account<'info, StakingAccount>,
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(
        mut,
        seeds = [b"protocol_vault"],
        bump,
        constraint = protocol_vault.owner == protocol.key() @ ErrorCode::InvalidOwner
    )]
    pub protocol_vault: Account<'info, TokenAccount>,
    #[account(mut)]
    pub user_rugme: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Buyback<'info> {
    #[account(mut, seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    #[account(
        mut,
        seeds = [b"protocol_vault"],
        bump,
        constraint = protocol_vault.owner == protocol.key() @ ErrorCode::InvalidOwner
    )]
    pub protocol_vault: Account<'info, TokenAccount>,
    #[account(mut)]
    pub burn_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct AnalyzeToken<'info> {
    #[account(seeds = [b"protocol"], bump = protocol.protocol_bump)]
    pub protocol: Account<'info, Protocol>,
    pub user: Signer<'info>,
}

/// Data structs
#[account]
pub struct Protocol {
    pub authority: Pubkey,
    pub rugme_mint: Pubkey,
    pub usdc_mint: Pubkey,
    pub total_supply: u64,
    pub insurance_pool: u64,
    pub staking_pool: u64,
    pub lottery_pool: u64,
    pub buyback_reserve: u64,
    pub total_staked: u64,
    pub total_policies: u64,
    pub total_votes: u64,
    pub total_premiums: u64,
    pub protocol_bump: u8,
    pub insurance_pool_pct: u8,
    pub staking_pool_pct: u8,
    pub lottery_pool_pct: u8,
    pub buyback_pool_pct: u8,
    pub rugme_price: u64,
    pub last_proposal_time: i64,
}

#[account]
pub struct InsurancePolicy {
    pub owner: Pubkey,
    pub token_insured: Pubkey,
    pub coverage_amount: u64,
    pub premium_amount: u64,
    pub start_time: i64,
    pub end_time: i64,
    pub is_active: bool,
    pub has_claimed: bool,
    pub policy_id: u64,
}

#[account]
pub struct UserPremiums {
    pub user: Pubkey,
    pub total_premium: u64,
}

#[account]
pub struct PremiumPayer {
    pub user: Pubkey,
    pub premium_amount: u64,
}

#[account]
pub struct StakingAccount {
    pub owner: Pubkey,
    pub amount: u64,
    pub last_claim: i64,
}

#[account]
pub struct VoteProposal {
    pub vote_id: u64,
    pub proposer: Pubkey,
    pub vote_type: VoteType,
    pub target: Pubkey,
    pub amount: u64,
    pub yes_votes: u64,
    pub no_votes: u64,
    pub start_time: i64,
    pub end_time: i64,
    pub is_active: bool,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum VoteType {
    Lottery,
    ClaimApproval,
    GovernanceChange { change_type: GovernanceChangeType, new_value: u64 },
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum GovernanceChangeType {
    InsurancePoolPct,
    StakingPoolPct,
    LotteryPoolPct,
    BuybackPoolPct,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    VeryHigh,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct RugPullRiskReport {
    pub token: Pubkey,
    pub risk_score: u8,
    pub holder_concentration: u8,
    pub liquidity_locked: bool,
    pub liquidity_amount: u64,
    pub dev_previous_rugs: u32,
    pub dev_token_count: u32,
    pub risk_level: RiskLevel,
}

/// Events
#[event]
pub struct ProtocolInitialized {
    pub authority: Pubkey,
    pub rugme_mint: Pubkey,
    pub usdc_mint: Pubkey,
    pub insurance_pool_pct: u8,
    pub staking_pool_pct: u8,
    pub lottery_pool_pct: u8,
    pub buyback_pool_pct: u8,
    pub rugme_price: u64,
}

#[event]
pub struct PolicyCreated {
    pub policy_id: u64,
    pub owner: Pubkey,
    pub token_insured: Pubkey,
    pub coverage_amount: u64,
    pub premium_amount: u64,
    pub start_time: i64,
    pub end_time: i64,
}

#[event]
pub struct PolicyCanceled {
    pub policy_id: u64,
    pub owner: Pubkey,
    pub refund_amount: u64,
}

#[event]
pub struct ClaimProposed {
    pub policy_id: u64,
    pub owner: Pubkey,
    pub coverage: u64,
}

#[event]
pub struct VoteProposed {
    pub vote_id: u64,
    pub proposer: Pubkey,
    pub vote_type: VoteType,
    pub target: Pubkey,
    pub amount: u64,
}

#[event]
pub struct LotteryProposed {
    pub winners: [Pubkey; 3],
    pub amounts: [u64; 3],
}

#[event]
pub struct LotteryWon {
    pub winner: Pubkey,
    pub amount: u64,
}

#[event]
pub struct PoolPercentagesUpdated {
    pub insurance_pool_pct: u8,
    pub staking_pool_pct: u8,
    pub lottery_pool_pct: u8,
    pub buyback_pool_pct: u8,
}

#[event]
pub struct PriceUpdated {
    pub new_price: u64,
    pub timestamp: i64,
}

#[event]
pub struct RewardsClaimed {
    pub user: Pubkey,
    pub amount: u64,
}

#[event]
pub struct BuybackExecuted {
    pub amount: u64,
    pub timestamp: i64,
}

#[event]
pub struct TokenAnalyzed {
    pub token: Pubkey,
    pub risk_score: u8,
    pub risk_level: RiskLevel,
}

#[event]
pub struct TransactionFailed {
    pub reason: String,
    pub user: Pubkey,
}

/// Helper functions
fn calculate_premium_usdc(coverage: u64, days: u64, risk: u8) -> Result<u64> {
    let volatility = fetch_market_volatility()?; // Mock: Fetch from Pyth
    let base_rate = match risk {
        0..=30 => 500,  // Low risk
        31..=60 => 1000, // Medium risk
        61..=80 => 1500, // High risk
        _ => 2000,       // Very high risk
    };
    let volatility_adjustment = 100 + (volatility * 50 / 100);
    let time_multiplier = match days {
        1..=7 => 100,
        8..=30 => 120,
        _ => 150,
    };
    let premium = coverage
        .checked_mul(base_rate)
        .ok_or(ErrorCode::Overflow)?
        .checked_mul(time_multiplier)
        .ok_or(ErrorCode::Overflow)?
        .checked_mul(volatility_adjustment)
        .ok_or(ErrorCode::Overflow)?
        .checked_div(100_000)
        .ok_or(ErrorCode::Underflow)?;
    Ok(premium)
}

fn fetch_risk_score(token: &Pubkey) -> Result<u8> {
    let liquidity = fetch_liquidity(token)?;
    let volume = fetch_trading_volume(token)?;
    let token_age = fetch_token_age(token)?;
    let holder_concentration = fetch_holder_concentration(token)?;
    let dev_history = fetch_dev_history(token)?;

    let liquidity_score = if liquidity > 1_000_000 { 20 } else if liquidity > 100_000 { 50 } else { 80 };
    let volume_score = if volume > 500_000 { 20 } else if volume > 50_000 { 50 } else { 80 };
    let age_score = if token_age > 365 { 20 } else if token_age > 90 { 50 } else { 80 };
    let concentration_score = if holder_concentration < 10 { 20 } else if holder_concentration < 50 { 50 } else { 80 };
    let dev_score = if dev_history.previous_rugs == 0 { 20 } else if dev_history.previous_rugs < 3 { 50 } else { 80 };

    let risk_score = ((liquidity_score as u64 + volume_score as u64 + age_score as u64 + concentration_score as u64 + dev_score as u64) / 5)
        .try_into()
        .unwrap_or(50);
    require!(risk_score <= 100, ErrorCode::InvalidRiskScore);
    Ok(risk_score)
}

fn fetch_vrf_winner(
    vrf_account: &AccountInfo,
    vrf_request_id: u64,
    premium_payers: &[Account<PremiumPayer>],
    page: u64,
    page_size: u64,
) -> Result<Pubkey> {
    let start = (page * page_size) as usize;
    let end = std::cmp::min(start + page_size as usize, premium_payers.len());
    require!(start < premium_payers.len(), ErrorCode::InvalidPage);

    let vrf_result = chainlink::vrf::consume_randomness(vrf_account, vrf_request_id)?;
    require!(vrf_result > 0, ErrorCode::InvalidVRFResult);

    let index = (vrf_result % (end - start) as u64) as usize + start;
    Ok(premium_payers[index].user)
}

fn calculate_staking_reward(staking_account: &StakingAccount, protocol: &Protocol) -> Result<u64> {
    let stake_share = staking_account.amount as u128;
    let total_staked = protocol.total_staked as u128;
    let pool = protocol.staking_pool as u128;
    let reward = (stake_share * pool / total_staked).try_into().unwrap_or(0);
    Ok(reward)
}

fn fetch_rug_pull_status(token: &Pubkey) -> Result<bool> {
    // Mock: Call rug pull oracle (e.g., check liquidity removal >90%)
    let liquidity_status = fetch_liquidity_status(token)?;
    Ok(!liquidity_status.locked || liquidity_status.amount < 1_000)
}

fn fetch_liquidity(token: &Pubkey) -> Result<u64> {
    // Mock: Fetch from Raydium or other DEX
    Ok(100_000)
}

fn fetch_trading_volume(token: &Pubkey) -> Result<u64> {
    // Mock: Fetch 24h volume from DEX
    Ok(50_000)
}

fn fetch_token_age(token: &Pubkey) -> Result<u64> {
    // Mock: Fetch days since mint
    Ok(30)
}

fn fetch_holder_concentration(token: &Pubkey) -> Result<u8> {
    // Mock: Percentage of tokens held by top 10 wallets
    Ok(40)
}

fn fetch_liquidity_status(token: &Pubkey) -> Result<LiquidityStatus> {
    // Mock: Check if liquidity is locked and amount
    Ok(LiquidityStatus {
        locked: true,
        amount: 100_000,
    })
}

fn fetch_dev_history(token: &Pubkey) -> Result<DevHistory> {
    // Mock: Check developer's previous tokens and rug pulls
    Ok(DevHistory {
        previous_rugs: 0,
        token_count: 1,
    })
}

fn fetch_market_volatility() -> Result<u64> {
    // Mock: Fetch from Pyth
    Ok(20)
}

#[derive(AnchorSerialize, AnchorDeserialize)]
struct LiquidityStatus {
    locked: bool,
    amount: u64,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
struct DevHistory {
    previous_rugs: u32,
    token_count: u32,
}

/// Account sizes
impl Protocol {
    const LEN: usize = 8 + 32 + 32 + 32 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 1 + 1 + 1 + 1 + 8 + 8;
}

impl InsurancePolicy {
    const LEN: usize = 8 + 32 + 32 + 8 + 8 + 8 + 8 + 1 + 1 + 8;
}

impl UserPremiums {
    const LEN: usize = 8 + 32 + 8;
}

impl PremiumPayer {
    const LEN: usize = 8 + 32 + 8;
}

impl StakingAccount {
    const LEN: usize = 8 + 32 + 8 + 8;
}

impl VoteProposal {
    const LEN: usize = 8 + 8 + 32 + 4 + 32 + 8 + 8 + 8 + 8 + 8 + 1;
}

impl RugPullRiskReport {
    const LEN: usize = 8 + 32 + 1 + 1 + 1 + 8 + 4 + 4 + 4;
}
