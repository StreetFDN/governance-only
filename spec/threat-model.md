# Threat Model

**Owner: SEC**
**Last Updated: 2026-01-20**

---

## Overview

This document identifies threats, attackers, and mitigations for the Street Governance system on Base L2. The system involves:
- **KLED Token**: ERC-20 with ERC20Votes for delegation
- **StreetGovernor**: Proposal lifecycle with staking (50K KLED) and slashing (10%)
- **EditSuggestions**: Community edit proposals (500 KLED stake)
- **Timelock**: Execution delay for approved proposals
- **FutarchyTreasury**: Prediction market-based treasury decisions (Future Sprint)
  - Conditional tokens: "If Pass" / "If Fail" outcome tokens
  - AMM pools for price discovery
  - Oracle-based resolution mechanism

---

## Assets

### Critical Assets

| Asset | Description | Threat Impact | Location |
|-------|-------------|---------------|----------|
| Staked KLED | 50,000 KLED per proposal | Direct financial loss | StreetGovernor |
| Edit Stakes | 500 KLED per suggestion | Direct financial loss | EditSuggestions |
| Treasury Funds | Protocol-controlled funds | Critical financial loss | Treasury/Timelock |
| Governance Power | Voting/proposal rights | Governance capture | KLED Token |
| Admin Keys | Contract upgrade authority | Complete system compromise | Multisig |

### High-Value Assets

| Asset | Description | Threat Impact | Location |
|-------|-------------|---------------|----------|
| Slashing Pool | Accumulated slashed tokens | Financial loss | StreetGovernor |
| Protocol Parameters | Stake amounts, voting periods | System manipulation | Governance Contracts |
| Snapshot Data | Voting power at proposal time | Vote manipulation | KLED Token (checkpoints) |

---

## Trust Assumptions

### What We Trust

| Entity/Component | Trust Assumption | Risk if Violated |
|------------------|------------------|------------------|
| Base Sequencer | Fair transaction inclusion | Vote censorship, MEV extraction |
| Ethereum L1 | Data availability & finality | Complete data loss |
| ERC20Votes (OZ) | Correct checkpoint implementation | Flash loan attacks possible |
| Multisig Signers (3/5+) | Act in protocol interest | Governance capture |

### What We Do NOT Trust

| Entity/Component | Why Untrusted | Mitigations |
|------------------|---------------|-------------|
| Individual Token Holders | May game system | Stake requirements, slashing |
| Flash Loan Providers | Enable capital-free attacks | Snapshot at proposal creation |
| MEV Searchers | Extract value, manipulate votes | Commit-reveal, delay mechanics |
| Proposers | May spam or grief | 50K stake, 10% slashing |
| Edit Suggesters | May game for stake return | 500 stake, community voting |

---

## Attacker Profiles

| Attacker | Resources | Motivation | Primary Vectors |
|----------|-----------|------------|-----------------|
| Griefing Attacker | 50K+ KLED | Disrupt governance | Proposal spam, stake attacks |
| Flash Loan Attacker | Access to DeFi | Governance capture | Instant voting power |
| Vote Buyer | Off-chain capital | Pass malicious proposals | Dark pool, bribery contracts |
| Whale Coordinator | Large KLED holdings | Control outcomes | Vote timing, snapshot gaming |
| Malicious Proposer | 50K KLED stake | Extract value | Malicious proposal execution |
| Edit Spammer | 500+ KLED | DoS edit system | Suggestion flooding |

---

## Attack Vectors by Category

### 1. Staking/Slashing Attack Vectors

#### STAKE-1: Stake Griefing Attack
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Attacker creates proposals designed to fail, accepting 10% slash (5K KLED) as cost to grief the system.

**Attack Scenario:**
1. Attacker acquires 50K KLED
2. Creates obviously bad proposals repeatedly
3. Each failure costs 5K KLED but floods governance
4. Legitimate proposals get buried; voter fatigue

**Impact:** DoS on governance, community frustration, wasted voter gas

**Mitigations:**
- [ ] Rate limit proposals per address (e.g., 1 active per address)
- [ ] Cooldown period after failed proposals (e.g., 7 days)
- [ ] Progressive slashing (10% → 20% → 40% for repeat failures)
- [ ] Reputation system affecting proposal visibility

---

#### STAKE-2: Flash Loan Stake Bypass
**Severity:** CRITICAL | **Likelihood:** HIGH (if not mitigated)

**Description:** Attacker uses flash loan to temporarily hold 50K KLED, creates proposal, repays loan in same tx.

**Attack Scenario:**
1. Flash borrow 50K KLED
2. Stake and create malicious proposal
3. Repay loan (0 cost except gas + fees)
4. Proposal exists with no real economic stake

**Impact:** Proposal threshold becomes meaningless; spam vector

**Mitigations:**
- [x] **REQUIRED:** Stake must be TRANSFERRED, not just held
- [x] **REQUIRED:** Lock stake for proposal duration (no unstake until resolution)
- [ ] Add `block.number` check: proposer balance at `block.number - 1` >= threshold

---

#### STAKE-3: Slashing Frontrun Protection
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Proposer sees their proposal failing and frontruns to cancel, avoiding slash.

**Attack Scenario:**
1. Proposer creates proposal with 50K stake
2. Monitors voting, sees it will fail
3. Submits cancel tx with high gas to frontrun vote close
4. Gets stake back, avoids 10% slash

**Impact:** Slashing mechanism undermined; no real skin-in-game

**Mitigations:**
- [ ] **REQUIRED:** No cancellation after voting starts
- [ ] Or: Apply partial slash on cancellation during voting (e.g., 5%)
- [ ] Use commit-reveal for vote tallying

---

#### STAKE-4: Stake Return Reentrancy
**Severity:** CRITICAL | **Likelihood:** MEDIUM (if vulnerable)

**Description:** Malicious token contract reenters during stake return.

**Attack Scenario:**
1. Attacker deploys malicious ERC-777/callback token (if KLED has hooks)
2. During `returnStake()` call, callback reenters
3. Multiple stake returns or state manipulation

**Impact:** Drain staking pool, corrupt proposal state

**Mitigations:**
- [x] **REQUIRED:** Use `ReentrancyGuard` on all stake/unstake functions
- [x] **REQUIRED:** Use CEI pattern (Checks-Effects-Interactions)
- [x] **REQUIRED:** KLED should be standard ERC-20 without callbacks

---

### 2. Voting Manipulation Attack Vectors

#### VOTE-1: Flash Loan Voting
**Severity:** CRITICAL | **Likelihood:** HIGH (if not mitigated)

**Description:** Attacker flash borrows tokens to vote, influencing outcome with no economic stake.

**Attack Scenario:**
1. Flash borrow large KLED amount at voting time
2. Vote on active proposal
3. Repay loan in same transaction
4. Zero-cost governance influence

**Impact:** Complete governance capture; economic security model broken

**Mitigations:**
- [x] **REQUIRED:** Snapshot voting power at proposal creation (`proposalSnapshot`)
- [x] **REQUIRED:** Use `ERC20Votes.getPastVotes(account, proposalSnapshot)` for vote weight
- [ ] Consider additional time-weighted voting multiplier

---

#### VOTE-2: Snapshot Gaming (Last-Block Accumulation)
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Attacker accumulates tokens right before proposal creation to maximize snapshot.

**Attack Scenario:**
1. Monitor mempool for `propose()` calls
2. Buy/borrow large KLED position
3. Front-run proposal creation
4. Snapshot captures inflated voting power

**Impact:** Unfair voting power distribution; potential governance capture

**Mitigations:**
- [ ] Snapshot at `proposalCreationBlock - 1` (exclude creation block)
- [ ] Add voting delay that allows rebalancing awareness
- [ ] Time-weighted voting (longer holders get more weight)
- [ ] Commit-reveal proposal creation

---

#### VOTE-3: Vote Buying / Dark Pools
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Off-chain or on-chain bribery for votes.

**Attack Scenario:**
1. Attacker creates bribery contract or off-chain agreement
2. Pays voters per vote weight contributed
3. Buys enough votes to pass malicious proposal
4. Executes harmful governance action

**Impact:** Governance captured by capital; community interest subverted

**Mitigations:**
- [ ] Vote privacy (commit-reveal, encrypted votes) - complex
- [ ] Veto power for guardian/security council
- [ ] Longer voting periods for community awareness
- [ ] Super-quorum for high-impact proposals

---

#### VOTE-4: Delegation Manipulation
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Attacker temporarily receives delegations, votes, then delegations removed.

**Attack Scenario:**
1. Attacker convinces users to delegate (social engineering, incentives)
2. Uses delegated power to vote on specific proposal
3. Users undelegate after damage done

**Impact:** Legitimate token holders' power used against their interest

**Mitigations:**
- [ ] Delegation changes take effect after voting delay
- [ ] Allow delegators to override delegate's vote
- [ ] Show delegation changes transparently in UI

---

#### VOTE-5: Abstain Quorum Gaming
**Severity:** MEDIUM | **Likelihood:** LOW

**Description:** Using abstain votes to help reach quorum for proposals that would otherwise fail.

**Attack Scenario:**
1. Proposal needs 40% quorum to be valid
2. Only 30% vote For, 5% vote Against
3. Attacker votes 10% Abstain to reach quorum
4. Proposal passes with minority support

**Impact:** Proposals pass without genuine majority support

**Mitigations:**
- [ ] Quorum counts only For + Against (not Abstain)
- [ ] Or: Separate quorum for participation vs approval threshold

---

### 3. L2-Specific Attack Vectors

#### L2-1: Sequencer Censorship During Voting
**Severity:** HIGH | **Likelihood:** LOW

**Description:** Sequencer selectively excludes transactions during critical voting period.

**Attack Scenario:**
1. Contentious proposal in voting period
2. Sequencer (or influencer of sequencer) censors opposing votes
3. Proposal passes/fails due to censored votes
4. Community recourse limited

**Impact:** Governance outcome manipulated; trust in system broken

**Mitigations:**
- [ ] Extended voting periods (allow L1 forced inclusion time)
- [ ] L1 escape hatch for emergency votes
- [ ] Grace period at voting end for delayed txs
- [ ] Monitor and alert on vote censorship patterns

---

#### L2-2: Reorg Vote Manipulation
**Severity:** MEDIUM | **Likelihood:** LOW (Base has strong sequencer)

**Description:** Attacker triggers or exploits L2 reorg to change vote outcome.

**Attack Scenario:**
1. Vote, see outcome going wrong direction
2. If reorg occurs, vote differently or abstain
3. Double-voting in parallel chains
4. Influence final outcome

**Impact:** Vote integrity compromised

**Mitigations:**
- [x] **REQUIRED:** Indexer handles reorgs (reprocess events)
- [ ] Sufficient confirmation depth before vote tallying
- [ ] Finality-aware UI (show "pending" until confirmed)
- [ ] On-chain vote tallying immune to indexer issues

---

#### L2-3: Sequencer Downtime Exploitation
**Severity:** MEDIUM | **Likelihood:** LOW

**Description:** Sequencer goes down during critical governance period.

**Attack Scenario:**
1. Controversial proposal in final voting hours
2. Sequencer experiences outage
3. Voters unable to participate
4. Proposal passes/fails with incomplete participation

**Impact:** Governance decisions without full participation

**Mitigations:**
- [ ] **REQUIRED:** Grace period extension if sequencer downtime detected
- [ ] Minimum voting duration (e.g., 72+ hours)
- [ ] Emergency pause by guardian if systemic issues
- [ ] L1 forced inclusion for critical votes

---

#### L2-4: Cross-L2 Replay Attacks
**Severity:** LOW | **Likelihood:** LOW

**Description:** Signature replay across different L2s if protocol deployed on multiple chains.

**Attack Scenario:**
1. User signs vote on Base
2. Same signature replayed on Optimism deployment
3. Unintended vote cast on other chain

**Impact:** Unintended voting across deployments

**Mitigations:**
- [x] **REQUIRED:** EIP-712 domain separator with chainId
- [x] **REQUIRED:** Include contract address in signature
- [ ] Nonce management per chain

---

### 4. Edit Suggestion Gaming Vectors

#### EDIT-1: Suggestion Spam Attack
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Flood proposals with low-quality edit suggestions.

**Attack Scenario:**
1. Attacker stakes 500 KLED per suggestion
2. Submits dozens of trivial/nonsense edits
3. Legitimate edits buried in noise
4. Voters suffer fatigue

**Impact:** Edit system unusable; governance quality degraded

**Mitigations:**
- [ ] Rate limit: max N suggestions per address per proposal
- [ ] Suggestion deposit burned if heavily rejected
- [ ] Reputation-weighted suggestion visibility
- [ ] Minimum approval threshold to reclaim stake

---

#### EDIT-2: Edit Timing Attack (48h Window)
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Submit edits at window boundaries to minimize scrutiny.

**Attack Scenario:**
1. Wait until hour 47 of 48h edit window
2. Submit malicious edit suggestion
3. Minimal time for community review
4. Edit might pass due to low scrutiny

**Impact:** Low-quality or malicious edits approved

**Mitigations:**
- [ ] Minimum review time for each suggestion (e.g., 24h from submission)
- [ ] Late suggestions extend voting window
- [ ] Highlight "late" suggestions prominently in UI

---

#### EDIT-3: Self-Voting on Suggestions
**Severity:** MEDIUM | **Likelihood:** HIGH

**Description:** Suggester votes on their own suggestion with large holdings.

**Attack Scenario:**
1. Whale submits edit suggestion
2. Immediately votes for own suggestion
3. Reaches approval threshold before others can review
4. Edit approved without genuine consensus

**Impact:** Suggestions approved without community buy-in

**Mitigations:**
- [ ] Suggester cannot vote on own suggestion
- [ ] Minimum number of unique voters (not just vote weight)
- [ ] Voting delay after suggestion creation

---

#### EDIT-4: Hash Collision / Text Manipulation
**Severity:** MEDIUM | **Likelihood:** LOW

**Description:** Manipulate edit text to appear benign but hash matches different content.

**Attack Scenario:**
1. Submit edit with `originalHash` that doesn't match actual proposal
2. Off-chain text shown differs from on-chain reference
3. Users vote on misleading edit

**Impact:** Confusing or malicious edits approved

**Mitigations:**
- [x] **REQUIRED:** Verify `originalHash` matches current proposal text on-chain
- [x] **REQUIRED:** Store proposed text hash on-chain, not just off-chain
- [ ] Show diff in UI with clear before/after

---

### 5. Economic/MEV Attack Vectors

#### MEV-1: Proposal Frontrunning
**Severity:** MEDIUM | **Likelihood:** HIGH

**Description:** MEV searchers frontrun valuable proposals.

**Attack Scenario:**
1. User submits proposal with valuable execution
2. MEV bot sees in mempool
3. Frontruns with their own proposal
4. Extracts value intended for protocol

**Impact:** Value leakage; user proposals griefed

**Mitigations:**
- [ ] Commit-reveal proposal submission
- [ ] Proposer exclusivity period
- [ ] Private mempool integration (Flashbots Protect)

---

#### MEV-2: Vote Sandwiching
**Severity:** LOW | **Likelihood:** MEDIUM

**Description:** Sandwich votes around governance token trades.

**Attack Scenario:**
1. Large vote incoming in mempool
2. MEV bot buys KLED before, sells after
3. Vote signals direction; speculation opportunity

**Impact:** Unfair extraction; governance signals leaked

**Mitigations:**
- [ ] Consider encrypted voting
- [ ] Randomized vote counting block

---

---

## 6. Futarchy Treasury Attack Vectors

The Futarchy system introduces prediction market mechanics for treasury decisions. Users trade conditional tokens ("If Pass" / "If Fail") and the relative prices determine the decision outcome.

### Futarchy System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    Futarchy Treasury                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ Conditional │    │    AMM      │    │  Resolution │         │
│  │   Token     │───►│   Pools     │───►│   Oracle    │         │
│  │  Factory    │    │ (If Pass/   │    │  (TWAP +    │         │
│  │             │    │  If Fail)   │    │   Resolve)  │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│         │                  │                  │                 │
│         ▼                  ▼                  ▼                 │
│  ┌─────────────────────────────────────────────────────┐       │
│  │              Treasury Execution                       │       │
│  │  (Execute if Pass price > Fail price at resolution)  │       │
│  └─────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Futarchy-Specific Assets

| Asset | Description | Threat Impact | Location |
|-------|-------------|---------------|----------|
| Treasury Collateral | Locked funds for conditional tokens | Direct theft | FutarchyTreasury |
| Conditional Tokens | If-Pass / If-Fail outcome tokens | Price manipulation | ConditionalTokenFactory |
| AMM Liquidity | LP positions in prediction pools | Impermanent loss, drain | FutarchyAMM |
| Resolution State | Final outcome determination | Wrong decision execution | ResolutionOracle |
| TWAP Accumulators | Time-weighted price data | Decision manipulation | FutarchyAMM |

---

### 6.1 Market Manipulation Attacks

#### FUT-1: Wash Trading Price Manipulation
**Severity:** CRITICAL | **Likelihood:** HIGH

**Description:** Attacker trades with themselves across multiple accounts to artificially inflate/deflate prices without real economic signal.

**Attack Scenario:**
1. Attacker controls addresses A and B
2. A buys large amount of "If Pass" tokens from AMM (price rises)
3. A sells "If Pass" tokens to B (off-AMM or same AMM)
4. B sells back to AMM, A buys again
5. Volume appears high, price is manipulated
6. Resolution uses manipulated price → wrong treasury decision

**Impact:** Treasury decisions based on fake market signal; potential drain of treasury

**Mitigations:**
- [x] **REQUIRED:** Use TWAP (Time-Weighted Average Price) for resolution, not spot price
- [x] **REQUIRED:** Minimum trading period before resolution (e.g., 72+ hours)
- [ ] Volume-weighted scoring (discount low-volume periods)
- [ ] On-chain detection of wash trading patterns
- [ ] Minimum unique traders requirement

---

#### FUT-2: Flash Loan AMM Manipulation
**Severity:** CRITICAL | **Likelihood:** HIGH

**Description:** Attacker flash loans collateral, mints conditional tokens, trades to manipulate price, then reverses in same transaction.

**Attack Scenario:**
1. Flash borrow 1M USDC
2. Mint 1M "If Pass" + 1M "If Fail" conditional tokens
3. Sell all "If Fail" tokens → "If Pass" price spikes
4. If resolution happens in same block: manipulated price used
5. Redeem remaining tokens, repay flash loan

**Impact:** Complete manipulation of treasury decision at zero cost

**Mitigations:**
- [x] **REQUIRED:** Resolution MUST use TWAP over multiple blocks (minimum 1 hour)
- [x] **REQUIRED:** Minimum time between last trade and resolution (e.g., 10 blocks)
- [ ] Block same-block manipulation: `require(block.number > lastTradeBlock[msg.sender])`
- [ ] Flash loan detection: compare balance at tx start vs during call

```solidity
// Required: TWAP-based resolution
function resolve(uint256 proposalId) external {
    require(block.timestamp >= tradingEndTime[proposalId], "Trading not ended");
    require(block.timestamp >= tradingEndTime[proposalId] + RESOLUTION_DELAY, "Delay not passed");

    // Use TWAP, not spot price
    uint256 passPrice = getTWAP(proposalId, PassToken, TWAP_WINDOW);
    uint256 failPrice = getTWAP(proposalId, FailToken, TWAP_WINDOW);

    bool shouldExecute = passPrice > failPrice;
    _resolve(proposalId, shouldExecute);
}
```

---

#### FUT-3: Front-Running Resolution
**Severity:** HIGH | **Likelihood:** HIGH

**Description:** Attacker sees resolution transaction in mempool, front-runs to position favorably, profits from predictable outcome.

**Attack Scenario:**
1. Trading period ends, resolution tx submitted
2. MEV bot sees resolution will favor "Pass" (based on TWAP)
3. Front-runs: buys "If Pass" tokens at current price
4. Resolution executes: "Pass" tokens become redeemable for full value
5. "Fail" tokens become worthless
6. Attacker profits from advance knowledge

**Impact:** Value extraction from honest market participants

**Mitigations:**
- [x] **REQUIRED:** Commit-reveal resolution (two-phase)
- [ ] Resolution only by trusted keeper/guardian with MEV protection
- [ ] Randomized resolution time within window
- [ ] Use Flashbots Protect or similar private mempool

```solidity
// Commit-reveal resolution
mapping(uint256 => bytes32) public resolutionCommitments;
mapping(uint256 => uint256) public commitBlock;

function commitResolution(uint256 proposalId, bytes32 commitment) external onlyKeeper {
    resolutionCommitments[proposalId] = commitment;
    commitBlock[proposalId] = block.number;
}

function revealResolution(uint256 proposalId, bool outcome, bytes32 salt) external {
    require(block.number >= commitBlock[proposalId] + REVEAL_DELAY, "Too early");
    require(keccak256(abi.encode(outcome, salt)) == resolutionCommitments[proposalId], "Invalid reveal");
    _resolve(proposalId, outcome);
}
```

---

#### FUT-4: Last-Block Price Spike
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Attacker waits until just before trading ends, executes large trade to spike price, TWAP window doesn't fully capture it.

**Attack Scenario:**
1. TWAP window is 1 hour, trading ends at block N
2. At block N-5, attacker dumps all "If Fail" tokens
3. "If Pass" price spikes for final minutes
4. TWAP partially incorporates spike
5. Marginal proposals flip outcome

**Impact:** Manipulation of close-call decisions; economic loss

**Mitigations:**
- [ ] Longer TWAP window (24+ hours recommended)
- [ ] Exclude final N blocks from TWAP calculation
- [ ] Cap single-trade price impact (max 5% slippage per trade)
- [ ] Median price instead of mean for outlier resistance

---

### 6.2 Oracle/Resolution Attacks

#### FUT-5: Oracle Manipulation
**Severity:** CRITICAL | **Likelihood:** MEDIUM

**Description:** If resolution relies on external price oracle (Chainlink, etc.), attacker manipulates oracle to affect outcome.

**Attack Scenario:**
1. Futarchy uses external oracle for "If Pass" vs "If Fail" resolution
2. Attacker manipulates oracle source (e.g., low-liquidity DEX)
3. Oracle reports manipulated price
4. Treasury decision based on false data

**Impact:** Complete governance capture via oracle manipulation

**Mitigations:**
- [x] **REQUIRED:** Use on-chain TWAP from protocol's own AMM, not external oracle
- [ ] If external oracle needed: use Chainlink with heartbeat checks
- [ ] Multiple oracle sources with median aggregation
- [ ] Circuit breaker if price deviation > threshold

---

#### FUT-6: Stale TWAP Attack
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** If TWAP accumulator isn't updated frequently, attacker can exploit gaps.

**Attack Scenario:**
1. TWAP relies on periodic observations
2. No trades for several hours → TWAP data stale
3. Attacker manipulates price, but TWAP averages old stale data
4. Result doesn't reflect actual market state

**Impact:** Inaccurate price signal; wrong decisions

**Mitigations:**
- [x] **REQUIRED:** Update TWAP accumulator on every trade
- [ ] Require minimum observation frequency
- [ ] Incentivize TWAP pokes (small reward for updating)
- [ ] Fallback to spot price if TWAP data insufficient

---

#### FUT-7: Resolution Griefing (Never Resolve)
**Severity:** MEDIUM | **Likelihood:** LOW

**Description:** If resolution requires external trigger and no incentive exists, proposals may never resolve, locking funds.

**Attack Scenario:**
1. Trading ends, proposal ready for resolution
2. No one calls resolve() (gas cost, no incentive)
3. Conditional tokens remain unredeemable
4. User funds locked indefinitely

**Impact:** User funds locked; system unusable

**Mitigations:**
- [x] **REQUIRED:** Anyone can call resolve() after trading ends
- [ ] Gas refund or reward for resolver
- [ ] Auto-resolution via keeper network (Chainlink Automation)
- [ ] Emergency guardian resolution after grace period

---

### 6.3 AMM-Specific Attacks

#### FUT-8: Liquidity Drain Attack
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Attacker exploits AMM vulnerabilities to drain liquidity.

**Attack Scenario:**
1. Find rounding error or edge case in AMM math
2. Repeatedly trade to accumulate rounding in attacker's favor
3. Drain LP funds over many transactions
4. Or: exploit reentrancy in swap/mint/burn functions

**Impact:** Loss of LP funds; market becomes illiquid

**Mitigations:**
- [x] **REQUIRED:** Use audited AMM implementation (Uniswap v2/v3 patterns)
- [x] **REQUIRED:** ReentrancyGuard on all AMM functions
- [ ] Invariant testing: k = x * y must hold after every operation
- [ ] Round in protocol's favor for all calculations

---

#### FUT-9: Sandwich Attack on Traders
**Severity:** MEDIUM | **Likelihood:** HIGH

**Description:** MEV bots sandwich user trades, extracting value.

**Attack Scenario:**
1. User submits buy order for "If Pass" tokens
2. MEV bot front-runs: buys "If Pass" (price rises)
3. User's tx executes at worse price
4. MEV bot back-runs: sells "If Pass" (profit)

**Impact:** Users receive worse prices; discourages participation

**Mitigations:**
- [x] **REQUIRED:** Slippage protection (user-specified max slippage)
- [ ] Minimum trade size (makes sandwiching less profitable)
- [ ] Use Flashbots Protect / private transactions
- [ ] Frequent batch auctions instead of continuous trading

```solidity
function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,  // REQUIRED: slippage protection
    uint256 deadline       // REQUIRED: expiry
) external nonReentrant {
    require(block.timestamp <= deadline, "Expired");
    uint256 amountOut = _calculateSwap(tokenIn, tokenOut, amountIn);
    require(amountOut >= minAmountOut, "Slippage exceeded");
    // ... execute swap
}
```

---

#### FUT-10: LP Impermanent Loss Griefing
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Attacker intentionally causes maximum impermanent loss to LPs.

**Attack Scenario:**
1. LPs provide liquidity at initial price
2. Attacker trades to extreme price
3. Attacker or others trade back
4. LPs suffer impermanent loss from the round trip
5. If pool fees don't cover IL, LPs lose money

**Impact:** LPs lose funds; liquidity providers exit

**Mitigations:**
- [ ] Higher swap fees during volatile periods
- [ ] Concentrated liquidity (Uniswap v3 style) - LP choice
- [ ] Protocol-owned liquidity to seed pools
- [ ] Cap price movement per block

---

### 6.4 Conditional Token Attacks

#### FUT-11: Dust Position Griefing
**Severity:** LOW | **Likelihood:** MEDIUM

**Description:** Attacker creates many tiny positions to bloat storage/gas costs.

**Attack Scenario:**
1. Attacker mints 1 wei of conditional tokens for many proposals
2. Contract storage grows with dust positions
3. Enumeration/cleanup becomes expensive
4. Or: attacker holds 1 wei to prevent certain cleanup operations

**Impact:** Gas griefing; state bloat; operational issues

**Mitigations:**
- [x] **REQUIRED:** Minimum trade/mint size (e.g., 0.01 ETH equivalent)
- [ ] Minimum position size for redemption
- [ ] Storage rent or cleanup incentives
- [ ] Batch operations for efficiency

```solidity
uint256 public constant MIN_MINT_AMOUNT = 1e16; // 0.01 ETH equivalent

function mintConditional(uint256 proposalId, uint256 amount) external {
    require(amount >= MIN_MINT_AMOUNT, "Amount too small");
    // ... mint logic
}
```

---

#### FUT-12: Conditional Token Reentrancy
**Severity:** CRITICAL | **Likelihood:** MEDIUM

**Description:** Reentrancy during conditional token mint/redeem operations.

**Attack Scenario:**
1. Conditional token uses ERC-1155 with callbacks
2. During mint/redeem, callback to attacker contract
3. Attacker reenters before state updated
4. Double mint or double redeem

**Impact:** Drain of collateral pool

**Mitigations:**
- [x] **REQUIRED:** ReentrancyGuard on mint/redeem
- [x] **REQUIRED:** CEI pattern
- [ ] Use ERC-20 for conditional tokens (no callbacks) if possible
- [ ] Or: carefully audit ERC-1155 callback handling

---

#### FUT-13: Split/Merge Accounting Errors
**Severity:** HIGH | **Likelihood:** MEDIUM

**Description:** Errors in conditional token split (collateral → outcome tokens) or merge (outcome tokens → collateral) accounting.

**Attack Scenario:**
1. User deposits 100 USDC collateral
2. Should receive 100 "If Pass" + 100 "If Fail" tokens
3. Bug: receives 100 "If Pass" + 100 "If Fail" + keeps 100 USDC
4. Or: merge returns more collateral than deposited

**Impact:** Infinite money glitch; drain protocol

**Mitigations:**
- [x] **REQUIRED:** Invariant: total_collateral = sum(redeemable_tokens / outcomes)
- [ ] Formal verification of token accounting
- [ ] Extensive fuzz testing of split/merge paths

---

### 6.5 Game Theory / Economic Attacks

#### FUT-14: Self-Fulfilling Prophecy Attack
**Severity:** HIGH | **Likelihood:** LOW

**Description:** Attacker manipulates market to create outcome that wouldn't otherwise occur.

**Attack Scenario:**
1. Proposal: "Should we hire Contractor X for $1M?"
2. Attacker is Contractor X or affiliated
3. Attacker buys massive "If Pass" position
4. Price signals community that "Pass" is favorable
5. Community follows price signal (information cascade)
6. Proposal passes; attacker profits + gets contract

**Impact:** Governance manipulation via manufactured consensus

**Mitigations:**
- [ ] Conflict of interest disclosures (off-chain, verified)
- [ ] Minimum market liquidity before decision is binding
- [ ] Veto power for guardian on suspicious outcomes
- [ ] Post-decision audit mechanism

---

#### FUT-15: Information Asymmetry Exploitation
**Severity:** MEDIUM | **Likelihood:** MEDIUM

**Description:** Insiders with private information trade before public announcement.

**Attack Scenario:**
1. Core team knows proposal will fail (internal decision)
2. Before announcement, team members short "If Pass"
3. Announcement made, price crashes
4. Insiders profit from advance knowledge

**Impact:** Unfair extraction from public participants

**Mitigations:**
- [ ] Trading blackout for core team during active proposals
- [ ] Delayed revelation of large positions
- [ ] Post-market audit of insider trading
- [ ] Anonymous voting/trading where possible

---

## Futarchy Required Security Patterns

### AMM Patterns

| Pattern | Purpose | Implementation | Status |
|---------|---------|----------------|--------|
| TWAP Oracle | Manipulation resistance | Accumulator updated on every trade | Required |
| Slippage Protection | User protection | `minAmountOut` parameter on all swaps | Required |
| Deadline Parameter | Replay protection | `deadline` timestamp on all swaps | Required |
| Min Trade Size | Dust/spam prevention | Configurable minimum (e.g., 0.01 ETH) | Required |
| Price Impact Cap | Manipulation limit | Max 10% price impact per trade | Recommended |

### Resolution Patterns

| Pattern | Purpose | Implementation | Status |
|---------|---------|----------------|--------|
| TWAP Resolution | Flash loan protection | 24h+ TWAP window | Required |
| Resolution Delay | Front-run protection | Min 10 blocks after trading ends | Required |
| Commit-Reveal | MEV protection | Two-phase resolution | Required |
| Anyone Can Resolve | Liveness guarantee | No access control on resolve() | Required |

### Token Patterns

| Pattern | Purpose | Implementation | Status |
|---------|---------|----------------|--------|
| Collateral Accounting | Solvency guarantee | Invariant: collateral = tokens / outcomes | Required |
| Min Mint Amount | Dust prevention | Minimum 0.01 ETH equivalent | Required |
| Reentrancy Guard | Security | On all mint/redeem/split/merge | Required |

---

## Futarchy Open Security Decisions

| Decision | Options | SEC Recommendation | Status |
|----------|---------|-------------------|--------|
| TWAP Window | 1h, 6h, 24h | 24h minimum | Pending ARCH |
| Min Trade Size | 0.001 ETH, 0.01 ETH, 0.1 ETH | 0.01 ETH | Pending ARCH |
| Resolution Delay | 1 block, 10 blocks, 1 hour | 10 blocks minimum | Pending ARCH |
| Conditional Token Standard | ERC-20, ERC-1155 | ERC-20 (simpler, no callbacks) | Pending ARCH |
| Price Impact Cap | None, 5%, 10% | 10% max per trade | Pending ARCH |
| LP Fee | 0.1%, 0.3%, 1% | 0.3% (standard) | Pending ARCH |

---

## Required Security Patterns

### Smart Contract Patterns

| Pattern | Purpose | Where to Apply | Status |
|---------|---------|----------------|--------|
| ReentrancyGuard | Prevent reentrancy | All stake/unstake, execute functions | Required |
| CEI (Checks-Effects-Interactions) | State consistency | All external calls | Required |
| SafeERC20 | Handle non-standard tokens | All token transfers | Required |
| Pausable | Emergency stop | Governor, EditSuggestions | Required |
| AccessControl | Role-based permissions | Admin functions | Required |

### Voting Patterns

| Pattern | Purpose | Implementation | Status |
|---------|---------|----------------|--------|
| Snapshot Voting | Flash loan protection | `proposalSnapshot = block.number` | Required |
| EIP-712 Signatures | Secure off-chain votes | Domain separator with chainId | Required |
| Vote Delegation | Governance participation | ERC20Votes checkpoints | Required |
| Quorum Validation | Prevent low-turnout gaming | Minimum participation threshold | Required |

### L2-Specific Patterns

| Pattern | Purpose | Implementation | Status |
|---------|---------|----------------|--------|
| Finality Awareness | Handle reorgs | Wait for confirmations | Required |
| Grace Periods | Sequencer downtime | Extend deadlines if needed | Recommended |
| L1 Escape Hatch | Censorship resistance | Force inclusion mechanism | Recommended |

---

## Security Controls Checklist

### Preventive Controls

- [ ] ReentrancyGuard on all external-facing state changes
- [ ] CEI pattern in all functions with external calls
- [ ] Input validation on all external inputs
- [ ] Access control on privileged functions (propose, execute, admin)
- [ ] Timelock on admin/governance execution
- [ ] Snapshot-based voting power
- [ ] Stake lockup during proposal lifecycle
- [ ] EIP-712 for any signature-based operations

### Detective Controls

- [ ] Event emission for all state changes
- [ ] On-chain monitoring for unusual patterns
- [ ] Vote weight anomaly detection
- [ ] Treasury balance monitoring
- [ ] Slashing event alerts

### Corrective Controls

- [ ] Pausable contracts with guardian role
- [ ] Emergency withdrawal mechanism
- [ ] Upgrade path via governance
- [ ] Guardian veto for malicious proposals

---

## Open Security Decisions

| Decision | Options | SEC Recommendation | Status |
|----------|---------|-------------------|--------|
| Proxy Pattern | UUPS, Transparent, None | UUPS (minimal proxy overhead) | Pending ARCH |
| Timelock Duration | 24h, 48h, 72h | 48h minimum | Pending ARCH |
| Flash Loan Protection | Snapshot only, Time-weighted | Snapshot + proposal delay | Pending ARCH |
| Cancellation Policy | Anytime, Before voting, Never | Before voting only | Pending ARCH |
| Suggestion Spam Protection | Rate limit, Burn on reject | Rate limit + partial burn | Pending ARCH |

---

## Known Accepted Risks

| Risk | Severity | Justification | Owner Sign-off |
|------|----------|---------------|----------------|
| Sequencer centralization | Medium | Base sequencer operated by Coinbase; L1 escape hatch available | Pending |
| 50K stake may be too low | Medium | Acceptable griefing cost for v1; adjustable via governance | Pending |
| 7-day withdrawal delay L2→L1 | Low | Standard optimistic rollup behavior; users informed | Pending |

---

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-20 | SEC | Comprehensive threat model for staking/slashing, voting, L2, edit gaming |
| 2026-01-20 | SEC | Added Futarchy Treasury threat vectors: market manipulation, AMM attacks, conditional tokens, resolution |
