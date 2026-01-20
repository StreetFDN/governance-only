// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ConditionalTokens} from "./ConditionalTokens.sol";
import {FutarchyAMM} from "./FutarchyAMM.sol";

/**
 * @title FutarchyTreasury
 * @author Street Governance
 * @notice Treasury governance via prediction markets - "Vote on values, bet on beliefs"
 * @dev Main orchestrator for the Futarchy system
 *
 * FLOW:
 * 1. createProposal() - Proposer stakes KLED + seeds liquidity
 * 2. buyOutcome() / sellOutcome() - Traders bet on outcomes during trading period
 * 3. closeTrading() - Trading ends, record final prices
 * 4. resolveMarket() - Determine winner based on market prices
 * 5. executeProposal() (if PASS wins) or reject (if FAIL wins)
 * 6. redeemWinnings() - Traders redeem winning tokens for KLED
 *
 * Invariants:
 * - FUT-1: KLED balance >= sum(unreturned stakes) + sum(market collateral)
 * - FUT-2: Proposal can only be executed if passWins == true
 * - FUT-7: Executed/Rejected/Canceled are terminal states
 */
contract FutarchyTreasury is Initializable, UUPSUpgradeable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                           ERRORS
    // =============================================================

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientApproval();
    error InvalidState();
    error ProposalNotFound();
    error TradingNotActive();
    error TradingNotClosed();
    error NotResolved();
    error AlreadyResolved();
    error NotProposer();
    error OnlyGuardian();
    error PassDidNotWin();
    error NoClearWinner();
    error TooEarly();
    error TradingAlreadyStarted();
    error ClosingDelayNotPassed();

    // =============================================================
    //                           ENUMS
    // =============================================================

    enum ProposalState {
        None,       // 0 - Doesn't exist
        Active,     // 1 - Trading open
        Closed,     // 2 - Trading closed, awaiting resolution
        Resolved,   // 3 - Outcome determined
        Executed,   // 4 - Proposal passed and executed
        Rejected,   // 5 - Proposal failed (FAIL won)
        Canceled    // 6 - Canceled by proposer/guardian
    }

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct FutarchyProposal {
        address proposer;
        bytes32 descriptionHash;      // IPFS hash of description
        address target;               // Contract to call if passed
        bytes data;                   // Encoded function call
        uint256 requestedAmount;      // KLED from treasury

        uint256 passMarketId;         // AMM market for PASS outcome
        uint256 failMarketId;         // AMM market for FAIL outcome

        uint48 tradingStart;
        uint48 tradingEnd;
        uint48 resolutionTime;        // When outcome can be measured

        uint256 proposerStake;        // KLED staked by proposer
        uint256 initialLiquidity;     // KLED seeded for markets
        ProposalState state;

        uint256 passPrice;            // Final price if PASS
        uint256 failPrice;            // Final price if FAIL
        bool passWins;                // True if PASS market won
    }

    // =============================================================
    //                           EVENTS
    // =============================================================

    event FutarchyProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address target,
        uint256 requestedAmount,
        bytes32 descriptionHash,
        uint256 passMarketId,
        uint256 failMarketId,
        uint48 tradingEnd,
        uint48 resolutionTime
    );

    event OutcomePurchased(
        uint256 indexed proposalId,
        address indexed buyer,
        bool isPass,
        uint256 kledSpent,
        uint256 tokensReceived,
        uint256 newPrice
    );

    event OutcomeSold(
        uint256 indexed proposalId,
        address indexed seller,
        bool isPass,
        uint256 tokensSold,
        uint256 kledReceived,
        uint256 newPrice
    );

    event TradingClosed(uint256 indexed proposalId, uint256 passPrice, uint256 failPrice);

    event MarketResolved(
        uint256 indexed proposalId,
        bool passWins,
        uint256 finalPassPrice,
        uint256 finalFailPrice
    );

    event ProposalExecuted(uint256 indexed proposalId, address target, uint256 amount);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    event WinningsRedeemed(
        uint256 indexed proposalId,
        address indexed redeemer,
        uint256 tokensRedeemed,
        uint256 kledReceived
    );

    event StakeReturned(uint256 indexed proposalId, address indexed proposer, uint256 amount);

    event TestModeEnabled(bool enabled);
    event EmergencyResolution(uint256 indexed proposalId, bool passWins, address guardian);

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice KLED token used for staking and collateral
    IERC20 public kledToken;

    /// @notice Conditional tokens for outcome positions
    ConditionalTokens public conditionalTokens;

    /// @notice AMM for price discovery
    FutarchyAMM public amm;

    /// @notice Treasury holding contract
    address public treasury;

    /// @notice Guardian address for emergency actions
    address public guardian;

    /// @notice Test mode flag
    bool public testMode;

    // Configuration
    uint256 public proposalStake;         // 50,000 KLED default
    uint256 public minLiquidity;          // 10,000 KLED default
    uint48 public tradingPeriod;          // 7 days default
    uint48 public resolutionDelay;        // 30 days default
    uint48 public closingDelay;           // 1 hour default (SEC-031 fix)
    uint256 public minPriceThreshold;     // 5500 = 55% threshold

    // Proposal storage
    uint256 public proposalCount;
    mapping(uint256 => FutarchyProposal) public proposals;

    // Track collateral per proposal for redemption
    mapping(uint256 => uint256) public proposalCollateral;

    /// @notice Storage gap for future upgrades
    uint256[40] private __gap;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //                         INITIALIZER
    // =============================================================

    /**
     * @notice Initialize the FutarchyTreasury
     * @param kledToken_ KLED token address
     * @param conditionalTokens_ ConditionalTokens contract
     * @param amm_ FutarchyAMM contract
     * @param treasury_ Treasury holding contract
     * @param guardian_ Guardian address for emergency actions
     */
    function initialize(
        address kledToken_,
        address conditionalTokens_,
        address amm_,
        address treasury_,
        address guardian_
    ) external initializer {
        if (kledToken_ == address(0)) revert ZeroAddress();
        if (conditionalTokens_ == address(0)) revert ZeroAddress();
        if (amm_ == address(0)) revert ZeroAddress();
        if (guardian_ == address(0)) revert ZeroAddress();

        kledToken = IERC20(kledToken_);
        conditionalTokens = ConditionalTokens(conditionalTokens_);
        amm = FutarchyAMM(amm_);
        treasury = treasury_;
        guardian = guardian_;

        // Default production configuration
        proposalStake = 50_000e18;
        minLiquidity = 10_000e18;
        tradingPeriod = 7 days;
        resolutionDelay = 30 days;
        closingDelay = 1 hours;    // SEC-031: Delay between trading end and close
        minPriceThreshold = 5500; // 55%
    }

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    // =============================================================
    //                    PROPOSAL CREATION
    // =============================================================

    /**
     * @notice Create a new futarchy proposal
     * @param target Contract to call if proposal passes
     * @param data Encoded function call
     * @param requestedAmount KLED requested from treasury
     * @param descriptionHash IPFS hash of proposal description
     * @param liquidity Initial liquidity for markets (on top of stake)
     * @return proposalId The created proposal's ID
     */
    function createProposal(
        address target,
        bytes calldata data,
        uint256 requestedAmount,
        bytes32 descriptionHash,
        uint256 liquidity
    ) external nonReentrant whenNotPaused returns (uint256 proposalId) {
        if (target == address(0)) revert ZeroAddress();
        if (liquidity < _getMinLiquidity()) revert InsufficientBalance();

        uint256 totalRequired = _getProposalStake() + liquidity;

        // Transfer stake + liquidity from proposer
        kledToken.safeTransferFrom(msg.sender, address(this), totalRequired);

        proposalId = ++proposalCount;

        // Create PASS and FAIL markets in AMM
        uint256 halfLiquidity = liquidity / 2;

        // Approve AMM to use liquidity (for internal accounting)
        // Note: AMM doesn't actually transfer tokens, just tracks virtual balances

        uint256 passMarketId = amm.createMarket(proposalId, true, halfLiquidity);
        uint256 failMarketId = amm.createMarket(proposalId, false, halfLiquidity);

        uint48 tradingEnd = uint48(block.timestamp) + _getTradingPeriod();
        uint48 resolutionTime = tradingEnd + _getResolutionDelay();

        proposals[proposalId] = FutarchyProposal({
            proposer: msg.sender,
            descriptionHash: descriptionHash,
            target: target,
            data: data,
            requestedAmount: requestedAmount,
            passMarketId: passMarketId,
            failMarketId: failMarketId,
            tradingStart: uint48(block.timestamp),
            tradingEnd: tradingEnd,
            resolutionTime: resolutionTime,
            proposerStake: _getProposalStake(),
            initialLiquidity: liquidity,
            state: ProposalState.Active,
            passPrice: 0,
            failPrice: 0,
            passWins: false
        });

        // Track collateral for this proposal
        proposalCollateral[proposalId] = liquidity;

        emit FutarchyProposalCreated(
            proposalId,
            msg.sender,
            target,
            requestedAmount,
            descriptionHash,
            passMarketId,
            failMarketId,
            tradingEnd,
            resolutionTime
        );
    }

    // =============================================================
    //                    TRADING FUNCTIONS
    // =============================================================

    /**
     * @notice Buy outcome tokens
     * @param proposalId Proposal to trade on
     * @param isPass True to buy PASS outcome, false for FAIL
     * @param kledAmount Amount of KLED to spend
     * @param minTokens Minimum tokens to receive (slippage protection)
     * @return tokensReceived Amount of outcome tokens received
     */
    function buyOutcome(
        uint256 proposalId,
        bool isPass,
        uint256 kledAmount,
        uint256 minTokens
    ) external nonReentrant whenNotPaused returns (uint256 tokensReceived) {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Active) revert TradingNotActive();
        if (block.timestamp >= proposal.tradingEnd) revert TradingNotActive();
        if (kledAmount == 0) revert ZeroAmount();

        // Transfer KLED from buyer
        kledToken.safeTransferFrom(msg.sender, address(this), kledAmount);

        // Get market ID
        uint256 marketId = isPass ? proposal.passMarketId : proposal.failMarketId;

        // Execute trade in AMM (updates virtual balances)
        // deadline = current block + 1 hour for safety margin
        (uint256 cost, uint256 tokens) = amm.buy(marketId, true, kledAmount, block.timestamp + 1 hours);
        tokensReceived = tokens;

        require(tokensReceived >= minTokens, "Slippage exceeded");

        // Mint outcome tokens to buyer
        conditionalTokens.mint(msg.sender, proposalId, isPass, tokensReceived);

        // Add to proposal collateral
        proposalCollateral[proposalId] += cost;

        // Get new price for event
        uint256 newPrice = amm.getPrice(marketId, true);

        emit OutcomePurchased(proposalId, msg.sender, isPass, cost, tokensReceived, newPrice);
    }

    /**
     * @notice Sell outcome tokens back
     * @param proposalId Proposal to trade on
     * @param isPass True to sell PASS tokens, false for FAIL
     * @param tokenAmount Amount of tokens to sell
     * @param minKled Minimum KLED to receive
     * @return kledReceived Amount of KLED received
     */
    function sellOutcome(
        uint256 proposalId,
        bool isPass,
        uint256 tokenAmount,
        uint256 minKled
    ) external nonReentrant whenNotPaused returns (uint256 kledReceived) {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Active) revert TradingNotActive();
        if (block.timestamp >= proposal.tradingEnd) revert TradingNotActive();
        if (tokenAmount == 0) revert ZeroAmount();

        // Check seller has tokens
        uint256 balance = conditionalTokens.balanceOfOutcome(msg.sender, proposalId, isPass);
        if (balance < tokenAmount) revert InsufficientBalance();

        // Get market ID
        uint256 marketId = isPass ? proposal.passMarketId : proposal.failMarketId;

        // Execute trade in AMM
        // deadline = current block + 1 hour for safety margin
        kledReceived = amm.sell(marketId, true, tokenAmount, minKled, block.timestamp + 1 hours);

        // Burn tokens from seller
        conditionalTokens.burn(msg.sender, proposalId, isPass, tokenAmount);

        // Deduct from proposal collateral
        proposalCollateral[proposalId] -= kledReceived;

        // Transfer KLED to seller
        kledToken.safeTransfer(msg.sender, kledReceived);

        // Get new price for event
        uint256 newPrice = amm.getPrice(marketId, true);

        emit OutcomeSold(proposalId, msg.sender, isPass, tokenAmount, kledReceived, newPrice);
    }

    // =============================================================
    //                    LIFECYCLE FUNCTIONS
    // =============================================================

    /**
     * @notice Close trading for a proposal
     * @dev SEC-031 fix: Requires closingDelay after tradingEnd to prevent front-running
     * @param proposalId Proposal to close
     */
    function closeTrading(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Active) revert InvalidState();
        if (block.timestamp < proposal.tradingEnd) revert TooEarly();
        // SEC-031: Add delay between trading end and close to prevent front-running
        if (block.timestamp < proposal.tradingEnd + _getClosingDelay()) revert ClosingDelayNotPassed();

        proposal.state = ProposalState.Closed;

        // Close markets and record final prices
        (uint256 passYesPrice,) = amm.closeMarket(proposal.passMarketId);
        (uint256 failYesPrice,) = amm.closeMarket(proposal.failMarketId);

        proposal.passPrice = passYesPrice;
        proposal.failPrice = failYesPrice;

        emit TradingClosed(proposalId, passYesPrice, failYesPrice);
    }

    /**
     * @notice Resolve market and determine winner
     * @param proposalId Proposal to resolve
     */
    function resolveMarket(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Closed) revert TradingNotClosed();
        if (block.timestamp < proposal.resolutionTime) revert TooEarly();

        // Compare market prices
        // Higher price = market believes this outcome is better
        bool passWins = proposal.passPrice >= proposal.failPrice;

        // Check for clear winner (avoid 50/50 ties)
        uint256 priceDiff;
        if (passWins) {
            priceDiff = proposal.passPrice - proposal.failPrice;
        } else {
            priceDiff = proposal.failPrice - proposal.passPrice;
        }

        // Convert to basis points (prices are in 1e18)
        uint256 diffBps = (priceDiff * 10000) / 1e18;
        if (diffBps < minPriceThreshold) revert NoClearWinner();

        proposal.state = ProposalState.Resolved;
        proposal.passWins = passWins;

        // Return stake to proposer
        kledToken.safeTransfer(proposal.proposer, proposal.proposerStake);

        emit StakeReturned(proposalId, proposal.proposer, proposal.proposerStake);
        emit MarketResolved(proposalId, passWins, proposal.passPrice, proposal.failPrice);
    }

    /**
     * @notice Execute a passed proposal
     * @param proposalId Proposal to execute
     */
    function executeProposal(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Resolved) revert NotResolved();
        if (!proposal.passWins) revert PassDidNotWin();

        proposal.state = ProposalState.Executed;

        // Execute the proposal action via treasury
        if (proposal.requestedAmount > 0 && proposal.target != address(0)) {
            // Transfer KLED from treasury to target
            IERC20(address(kledToken)).safeTransferFrom(
                treasury,
                proposal.target,
                proposal.requestedAmount
            );
        }

        emit ProposalExecuted(proposalId, proposal.target, proposal.requestedAmount);
    }

    /**
     * @notice Mark a failed proposal as rejected
     * @param proposalId Proposal to reject
     */
    function rejectProposal(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Resolved) revert NotResolved();
        if (proposal.passWins) revert InvalidState(); // Should use execute instead

        proposal.state = ProposalState.Rejected;

        emit ProposalRejected(proposalId);
    }

    /**
     * @notice Redeem winning outcome tokens for KLED
     * @param proposalId Proposal to redeem from
     */
    function redeemWinnings(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];

        // Can only redeem after resolution
        if (proposal.state != ProposalState.Executed &&
            proposal.state != ProposalState.Rejected) {
            revert NotResolved();
        }

        // Determine which outcome won
        bool winningOutcome = proposal.passWins;

        // Get user's balance of winning tokens
        uint256 winningBalance = conditionalTokens.balanceOfOutcome(
            msg.sender,
            proposalId,
            winningOutcome
        );

        if (winningBalance == 0) revert ZeroAmount();

        // Calculate share of collateral pool
        uint256 totalWinningTokens = conditionalTokens.totalSupplyOfOutcome(
            proposalId,
            winningOutcome
        );

        uint256 payout = (winningBalance * proposalCollateral[proposalId]) / totalWinningTokens;

        // Burn winning tokens
        conditionalTokens.burn(msg.sender, proposalId, winningOutcome, winningBalance);

        // Deduct from collateral
        proposalCollateral[proposalId] -= payout;

        // Transfer KLED to redeemer
        kledToken.safeTransfer(msg.sender, payout);

        emit WinningsRedeemed(proposalId, msg.sender, winningBalance, payout);
    }

    /**
     * @notice Cancel a proposal
     * @dev SEC-032 fix: Proposer can only cancel before any trades occur
     * @param proposalId Proposal to cancel
     */
    function cancelProposal(uint256 proposalId) external nonReentrant {
        FutarchyProposal storage proposal = proposals[proposalId];

        // Proposer can cancel during Active ONLY if no trades have occurred
        // Guardian can cancel during Active or Closed (emergency power)
        bool isProposer = msg.sender == proposal.proposer;
        bool isGuardian = msg.sender == guardian;

        if (proposal.state == ProposalState.Active) {
            if (isProposer) {
                // SEC-032: Proposer can only cancel if no trading has occurred
                // Trading has occurred if collateral > initial liquidity
                if (proposalCollateral[proposalId] > proposal.initialLiquidity) {
                    revert TradingAlreadyStarted();
                }
            } else if (!isGuardian) {
                revert NotProposer();
            }
        } else if (proposal.state == ProposalState.Closed) {
            if (!isGuardian) revert OnlyGuardian();
        } else {
            revert InvalidState();
        }

        proposal.state = ProposalState.Canceled;

        // Return full stake to proposer
        kledToken.safeTransfer(proposal.proposer, proposal.proposerStake);

        // Return liquidity to proposer
        kledToken.safeTransfer(proposal.proposer, proposal.initialLiquidity);

        emit StakeReturned(proposalId, proposal.proposer, proposal.proposerStake);
        emit ProposalCanceled(proposalId);
    }

    // =============================================================
    //                    GUARDIAN FUNCTIONS
    // =============================================================

    /**
     * @notice Emergency resolve a market
     * @param proposalId Proposal to resolve
     * @param passWins True if PASS wins, false if FAIL wins
     */
    function emergencyResolve(uint256 proposalId, bool passWins) external onlyGuardian {
        FutarchyProposal storage proposal = proposals[proposalId];
        if (proposal.state != ProposalState.Closed) revert TradingNotClosed();

        proposal.state = ProposalState.Resolved;
        proposal.passWins = passWins;

        // Return stake to proposer
        kledToken.safeTransfer(proposal.proposer, proposal.proposerStake);

        emit StakeReturned(proposalId, proposal.proposer, proposal.proposerStake);
        emit EmergencyResolution(proposalId, passWins, msg.sender);
    }

    /**
     * @notice Enable or disable test mode
     * @param enabled True to enable test mode
     */
    function setTestMode(bool enabled) external onlyGuardian {
        testMode = enabled;
        emit TestModeEnabled(enabled);
    }

    /**
     * @notice Pause all trading and proposals
     */
    function pause() external onlyGuardian {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyGuardian {
        _unpause();
    }

    // =============================================================
    //                    CONFIGURATION
    // =============================================================

    /**
     * @notice Set proposal stake amount (governance only)
     */
    function setProposalStake(uint256 stake) external onlyGuardian {
        proposalStake = stake;
    }

    /**
     * @notice Set minimum liquidity (governance only)
     */
    function setMinLiquidity(uint256 liquidity) external onlyGuardian {
        minLiquidity = liquidity;
    }

    /**
     * @notice Set trading period (governance only)
     */
    function setTradingPeriod(uint48 period) external onlyGuardian {
        tradingPeriod = period;
    }

    /**
     * @notice Set resolution delay (governance only)
     */
    function setResolutionDelay(uint48 delay) external onlyGuardian {
        resolutionDelay = delay;
    }

    /**
     * @notice Set closing delay (governance only)
     * @dev SEC-031: Delay between trading end and when closeTrading can be called
     */
    function setClosingDelay(uint48 delay) external onlyGuardian {
        closingDelay = delay;
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get proposal state
     */
    function getProposalState(uint256 proposalId) external view returns (ProposalState) {
        return proposals[proposalId].state;
    }

    /**
     * @notice Get current prices for a proposal's markets
     */
    function getMarketPrices(uint256 proposalId) external view returns (
        uint256 passPrice,
        uint256 failPrice
    ) {
        FutarchyProposal storage proposal = proposals[proposalId];
        passPrice = amm.getPrice(proposal.passMarketId, true);
        failPrice = amm.getPrice(proposal.failMarketId, true);
    }

    // =============================================================
    //                    INTERNAL HELPERS
    // =============================================================

    function _getProposalStake() internal view returns (uint256) {
        if (testMode) return 100e18;
        return proposalStake;
    }

    function _getMinLiquidity() internal view returns (uint256) {
        if (testMode) return 10e18;
        return minLiquidity;
    }

    function _getTradingPeriod() internal view returns (uint48) {
        if (testMode) return 10 minutes;
        return tradingPeriod;
    }

    function _getResolutionDelay() internal view returns (uint48) {
        if (testMode) return 1 hours;
        return resolutionDelay;
    }

    function _getClosingDelay() internal view returns (uint48) {
        if (testMode) return 1 minutes;  // Short delay for testing
        return closingDelay;
    }

    // =============================================================
    //                      UUPS UPGRADE
    // =============================================================

    function _authorizeUpgrade(address) internal override onlyGuardian {}
}
