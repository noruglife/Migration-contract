use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer, MintTo, Burn};

declare_id!("RuGME11111111111111111111111111111111111111");

#[program]
pub mod rugme_migration {
    use super::*;

    // ---------------------------------
    // Initialize migration protocol
    // ---------------------------------
    pub fn initialize_migration(
        ctx: Context<InitializeMigration>,
        pump_fun_mint: Pubkey,
    ) -> Result<()> {
        let migration = &mut ctx.accounts.migration;
        let protocol = &mut ctx.accounts.protocol;

        // Migration params
        migration.pump_fun_mint = pump_fun_mint;
        migration.new_mint = ctx.accounts.new_mint.key();
        migration.migration_ratio = 1;
        migration.migration_start = Clock::get()?.unix_timestamp;
        migration.migration_end = migration.migration_start + (7 * 24 * 3600);
        migration.total_migrated = 0;
        migration.migration_active = true;
        migration.bonus_multiplier = 110; // 10% bonus
        migration.bonus_deadline = migration.migration_start + (48 * 3600);

        // Protocol params
        protocol.authority = ctx.accounts.authority.key();
        protocol.rugme_mint = ctx.accounts.new_mint.key();
        protocol.usdc_mint = ctx.accounts.usdc_mint.key();
        protocol.total_supply = 1_000_000_000 * 10u64.pow(9);
        protocol.insurance_pool = 0;
        protocol.staking_pool = 0;
        protocol.lottery_pool = 0;
        protocol.buyback_reserve = 0;
        protocol.total_staked = 0;
        protocol.total_policies = 0;
        protocol.protocol_bump = *ctx.bumps.get("protocol").unwrap();

        // Mint supply to migration vault
        let seeds = &[b"protocol", &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = MintTo {
            mint: ctx.accounts.new_mint.to_account_info(),
            to: ctx.accounts.migration_vault.to_account_info(),
            authority: ctx.accounts.protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::mint_to(cpi_ctx, protocol.total_supply)?;

        Ok(())
    }

    // ---------------------------------
    // Migrate from pump.fun -> NORUG
    // ---------------------------------
    pub fn migrate_tokens(
        ctx: Context<MigrateTokens>,
        amount: u64,
    ) -> Result<()> {
        let migration = &mut ctx.accounts.migration;
        let protocol = &mut ctx.accounts.protocol;

        require!(migration.migration_active, ErrorCode::MigrationInactive);
        require!(
            Clock::get()?.unix_timestamp <= migration.migration_end,
            ErrorCode::MigrationEnded
        );
        require!(amount > 0, ErrorCode::InvalidAmount);
        require!(ctx.accounts.user_old_tokens.amount >= amount, ErrorCode::InvalidAmount);

        // Calculate new amount
        let current_time = Clock::get()?.unix_timestamp;
        let new_amount = if current_time <= migration.bonus_deadline {
            (amount * migration.bonus_multiplier) / 100
        } else {
            amount * migration.migration_ratio
        };

        // Quarantine pump.fun tokens
        let cpi_accounts = Transfer {
            from: ctx.accounts.user_old_tokens.to_account_info(),
            to: ctx.accounts.burn_vault.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::transfer(cpi_ctx, amount)?;

        // Send new tokens
        let seeds = &[b"protocol", &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: ctx.accounts.migration_vault.to_account_info(),
            to: ctx.accounts.user_new_tokens.to_account_info(),
            authority: ctx.accounts.protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::transfer(cpi_ctx, new_amount)?;

        migration.total_migrated += amount;

        emit!(TokensMigrated {
            user: ctx.accounts.user.key(),
            old_amount: amount,
            new_amount,
            bonus_applied: current_time <= migration.bonus_deadline,
        });

        Ok(())
    }

    // ---------------------------------
    // Buy insurance
    // ---------------------------------
    pub fn buy_insurance(
        ctx: Context<BuyInsurance>,
        token_to_insure: Pubkey,
        coverage_amount: u64,
        coverage_days: u64,
    ) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let policy = &mut ctx.accounts.policy;

        require!(coverage_amount >= 10 * 10u64.pow(6), ErrorCode::MinimumCoverage);
        require!(coverage_days >= 1 && coverage_days <= 90, ErrorCode::InvalidDuration);

        let risk_score = 80u8; // simplified
        let premium_usdc = calculate_premium_usdc(coverage_amount, coverage_days, risk_score);
        let rugme_price = 5000u64; // $0.005
        let premium_rugme = (premium_usdc * 10u64.pow(9)) / rugme_price;

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_rugme.to_account_info(),
            to: ctx.accounts.protocol_vault.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::transfer(cpi_ctx, premium_rugme)?;

        policy.policy_id = protocol.total_policies;
        policy.owner = ctx.accounts.user.key();
        policy.token_insured = token_to_insure;
        policy.coverage_amount = coverage_amount;
        policy.premium_paid = premium_rugme;
        policy.start_time = Clock::get()?.unix_timestamp;
        policy.end_time = policy.start_time + (coverage_days as i64 * 86400);
        policy.is_active = true;
        policy.has_claimed = false;

        protocol.insurance_pool += premium_rugme * 25 / 100;
        protocol.staking_pool += premium_rugme * 35 / 100;
        protocol.lottery_pool += premium_rugme * 20 / 100;
        protocol.buyback_reserve += premium_rugme * 20 / 100;
        protocol.total_policies += 1;

        emit!(PolicyCreated {
            policy_id: policy.policy_id,
            owner: policy.owner,
            token: token_to_insure,
            coverage: coverage_amount,
            premium: premium_rugme,
        });

        Ok(())
    }

    // ---------------------------------
    // Stake tokens
    // ---------------------------------
    pub fn stake_tokens(
        ctx: Context<StakeTokens>,
        amount: u64,
    ) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let staking_account = &mut ctx.accounts.staking_account;

        require!(amount >= 1000 * 10u64.pow(9), ErrorCode::MinimumStake);

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_rugme.to_account_info(),
            to: ctx.accounts.staking_vault.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::transfer(cpi_ctx, amount)?;

        if staking_account.amount == 0 {
            staking_account.owner = ctx.accounts.user.key();
            staking_account.stake_time = Clock::get()?.unix_timestamp;
        }
        staking_account.amount += amount;
        staking_account.last_claim = Clock::get()?.unix_timestamp;

        protocol.total_staked += amount;

        emit!(TokensStaked {
            user: ctx.accounts.user.key(),
            amount,
            total_staked: staking_account.amount,
        });

        Ok(())
    }

    // ---------------------------------
    // Claim staking rewards
    // ---------------------------------
    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        let staking_account = &mut ctx.accounts.staking_account;

        let time_staked = Clock::get()?.unix_timestamp - staking_account.last_claim;
        require!(time_staked >= 3600, ErrorCode::TooEarly);

        let daily_pool_share = if protocol.total_staked > 0 {
            (protocol.staking_pool * staking_account.amount) / protocol.total_staked
        } else {
            0
        };
        let rewards = (daily_pool_share * time_staked as u64) / 86400;
        require!(rewards > 0, ErrorCode::NoRewards);

        let seeds = &[b"protocol", &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: ctx.accounts.staking_vault.to_account_info(),
            to: ctx.accounts.user_rugme.to_account_info(),
            authority: ctx.accounts.protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::transfer(cpi_ctx, rewards)?;

        staking_account.last_claim = Clock::get()?.unix_timestamp;
        staking_account.rewards_earned += rewards;
        protocol.staking_pool -= rewards;

        emit!(RewardsClaimed {
            user: ctx.accounts.user.key(),
            amount: rewards,
        });

        Ok(())
    }

    // ---------------------------------
    // Submit claim
    // ---------------------------------
    pub fn submit_claim(
        ctx: Context<SubmitClaim>,
        evidence: String,
    ) -> Result<()> {
        let policy = &ctx.accounts.policy;
        let claim = &mut ctx.accounts.claim;

        require!(policy.is_active, ErrorCode::PolicyInactive);
        require!(!policy.has_claimed, ErrorCode::AlreadyClaimed);
        require!(
            Clock::get()?.unix_timestamp <= policy.end_time,
            ErrorCode::PolicyExpired
        );

        let is_rugged = verify_pump_fun_rug(&policy.token_insured)?;
        require!(is_rugged, ErrorCode::NotRugged);

        claim.claim_id = Clock::get()?.unix_timestamp as u64;
        claim.policy_id = policy.policy_id;
        claim.claimant = ctx.accounts.user.key();
        claim.token_rugged = policy.token_insured;
        claim.amount_claimed = policy.coverage_amount;
        claim.evidence = evidence;
        claim.status = ClaimStatus::AutoApproved;
        claim.created_at = Clock::get()?.unix_timestamp;

        emit!(ClaimSubmitted {
            claim_id: claim.claim_id,
            claimant: claim.claimant,
            amount: claim.amount_claimed,
        });

        Ok(())
    }

    // ---------------------------------
    // Process claim
    // ---------------------------------
    pub fn process_claim(ctx: Context<ProcessClaim>) -> Result<()> {
        let claim = &mut ctx.accounts.claim;
        let policy = &mut ctx.accounts.policy;
        let protocol = &mut ctx.accounts.protocol;

        require!(claim.status == ClaimStatus::AutoApproved, ErrorCode::ClaimNotApproved);

        let available_funds = protocol.insurance_pool;
        let payout = if available_funds >= claim.amount_claimed {
            claim.amount_claimed
        } else {
            available_funds * 80 / 100
        };
        require!(payout > 0, ErrorCode::InsufficientFunds);

        let seeds = &[b"protocol", &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Transfer {
            from: ctx.accounts.protocol_vault.to_account_info(),
            to: ctx.accounts.claimant_rugme.to_account_info(),
            authority: ctx.accounts.protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::transfer(cpi_ctx, payout)?;

        claim.status = ClaimStatus::Paid;
        policy.has_claimed = true;
        protocol.insurance_pool -= payout;

        emit!(ClaimPaid {
            claim_id: claim.claim_id,
            amount: payout,
            claimant: claim.claimant,
        });

        Ok(())
    }

    // ---------------------------------
    // Execute buyback
    // ---------------------------------
    pub fn execute_buyback(ctx: Context<ExecuteBuyback>) -> Result<()> {
        let protocol = &mut ctx.accounts.protocol;
        require!(protocol.buyback_reserve > 0, ErrorCode::NoBuybackFunds);

        let burn_amount = protocol.buyback_reserve;

        let seeds = &[b"protocol", &[protocol.protocol_bump]];
        let signer = &[&seeds[..]];
        let cpi_accounts = Burn {
            mint: ctx.accounts.rugme_mint.to_account_info(),
            from: ctx.accounts.protocol_vault.to_account_info(),
            authority: ctx.accounts.protocol.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer);
        token::burn(cpi_ctx, burn_amount)?;

        protocol.total_supply -= burn_amount;
        protocol.buyback_reserve = 0;

        emit!(TokensBurned {
            amount: burn_amount,
            new_supply: protocol.total_supply,
        });

        Ok(())
    }
}

// ---------------------------------
// Helpers
// ---------------------------------
fn calculate_premium_usdc(coverage: u64, days: u64, risk: u8) -> u64 {
    let base_rate = match risk {
        0..=30 => 500,
        31..=60 => 1000,
        61..=80 => 1500,
        _ => 2000,
    };
    let time_multiplier = match days {
        1..=7 => 100,
        8..=30 => 120,
        _ => 150,
    };
    (coverage * base_rate * time_multiplier) / 100000
}

fn verify_pump_fun_rug(_token: &Pubkey) -> Result<bool> {
    Ok(true)
}

// ---------------------------------
// Accounts
// ---------------------------------
#[account]
pub struct Migration {
    pub pump_fun_mint: Pubkey,
    pub new_mint: Pubkey,
    pub migration_ratio: u64,
    pub migration_start: i64,
    pub migration_end: i64,
    pub total_migrated: u64,
    pub migration_active: bool,
    pub bonus_multiplier: u64,
    pub bonus_deadline: i64,
}

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
    pub protocol_bump: u8,
}

#[account]
pub struct InsurancePolicy {
    pub policy_id: u64,
    pub owner: Pubkey,
    pub token_insured: Pubkey,
    pub coverage_amount: u64,
    pub premium_paid: u64,
    pub start_time: i64,
    pub end_time: i64,
    pub is_active: bool,
    pub has_claimed: bool,
}

#[account]
pub struct StakingAccount {
    pub owner: Pubkey,
    pub amount: u64,
    pub rewards_earned: u64,
    pub stake_time: i64,
    pub last_claim: i64,
}

#[account]
pub struct Claim {
    pub claim_id: u64,
    pub policy_id: u64,
    pub claimant: Pubkey,
    pub token_rugged: Pubkey,
    pub amount_claimed: u64,
    pub evidence: String,
    pub status: ClaimStatus,
    pub created_at: i64,
}

// ---------------------------------
// Enums
// ---------------------------------
#[derive(AnchorSerialize, AnchorDeserialize, Clone, PartialEq)]
pub enum ClaimStatus {
    Pending,
    AutoApproved,
    Rejected,
    Paid,
}

// ---------------------------------
// Contexts
// ---------------------------------
#[derive(Accounts)]
pub struct InitializeMigration<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 8 + 8 + 8 + 1 + 8 + 8,
        seeds = [b"migration"],
        bump
    )]
    pub migration: Account<'info, Migration>,

    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 32 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 1,
        seeds = [b"protocol"],
        bump
    )]
    pub protocol: Account<'info, Protocol>,

    #[account(
        init,
        payer = authority,
        mint::decimals = 9,
        mint::authority = protocol,
        seeds = [b"rugme_mint"],
        bump
    )]
    pub new_mint: Account<'info, Mint>,

    pub usdc_mint: Account<'info, Mint>,

    #[account(
        init,
        payer = authority,
        token::mint = new_mint,
        token::authority = protocol,
        seeds = [b"migration_vault"],
        bump
    )]
    pub migration_vault: Account<'info, TokenAccount>,

    #[account(
        init,
        payer = authority,
        token::mint = pump_fun_mint,
        token::authority = protocol,
        seeds = [b"burn_vault"],
        bump
    )]
    pub burn_vault: Account<'info, TokenAccount>,

    pub system_program: Program<'info, System>,
    pub token_program:
        
