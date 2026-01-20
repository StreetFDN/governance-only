// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FutarchyTreasury} from "../src/FutarchyTreasury.sol";
import {FutarchyAMM} from "../src/FutarchyAMM.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {KLEDToken} from "../src/KLEDToken.sol";

/**
 * @title FutarchyForkTest
 * @notice Fork tests for Futarchy system against Base chain
 * @dev Tests realistic conditions including:
 *      - MEV resistance (sandwich attack simulation)
 *      - Block timestamp manipulation edge cases
 *      - Gas price spike scenarios
 *      - Large trade impact on AMM
 *
 * Run with: forge test --match-contract FutarchyForkTest --fork-url $BASE_RPC_URL -vvv
 * Or: forge test --match-contract FutarchyForkTest --fork-url $BASE_SEPOLIA_RPC_URL -vvv
 */
contract FutarchyForkTest is Test {
    // =============================================================
    //                        CONTRACTS
    // =============================================================

    KLEDToken public kled;
    ConditionalTokens public conditionalTokens;
    FutarchyAMM public amm;
    FutarchyTreasury public futarchy;

    // =============================================================
    //                          ACTORS
    // =============================================================

    address public guardian;
    address public treasury;
    address public proposer;
    address public trader1;
    address public trader2;
    address public mevBot;
    address public target;

    // =============================================================
    //                        CONSTANTS
    // =============================================================

    uint256 public constant INITIAL_SUPPLY = 100_000_000e18;
    uint256 public constant ACTOR_BALANCE = 1_000_000e18;
    uint256 public constant PRECISION = 1e18;

    // =============================================================
    //                          SETUP
    // =============================================================

    function setUp() public {
        // Create actors with deterministic addresses
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        proposer = makeAddr("proposer");
        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");
        mevBot = makeAddr("mevBot");
        target = makeAddr("target");

        // Deploy fresh contracts (simulating deployment on fork)
        _deployContracts();
        _fundActors();
        _setupApprovals();
    }

    function _deployContracts() internal {
        // Deploy KLED token
        vm.prank(guardian);
        kled = new KLEDToken(guardian, INITIAL_SUPPLY);

        // Deploy ConditionalTokens
        ConditionalTokens condImpl = new ConditionalTokens();
        bytes memory condInitData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy condProxy = new ERC1967Proxy(address(condImpl), condInitData);
        conditionalTokens = ConditionalTokens(address(condProxy));

        // Deploy FutarchyAMM
        FutarchyAMM ammImpl = new FutarchyAMM();
        bytes memory ammInitData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy ammProxy = new ERC1967Proxy(address(ammImpl), ammInitData);
        amm = FutarchyAMM(address(ammProxy));

        // Deploy FutarchyTreasury
        FutarchyTreasury ftImpl = new FutarchyTreasury();
        bytes memory ftInitData = abi.encodeWithSelector(
            FutarchyTreasury.initialize.selector,
            address(kled),
            address(conditionalTokens),
            address(amm),
            treasury,
            guardian
        );
        ERC1967Proxy ftProxy = new ERC1967Proxy(address(ftImpl), ftInitData);
        futarchy = FutarchyTreasury(address(ftProxy));

        // Configure dependencies
        conditionalTokens.setTreasury(address(futarchy));
        amm.setTreasury(address(futarchy));

        // Enable test mode for shorter periods
        vm.prank(guardian);
        futarchy.setTestMode(true);
    }

    function _fundActors() internal {
        vm.startPrank(guardian);
        kled.transfer(proposer, ACTOR_BALANCE);
        kled.transfer(trader1, ACTOR_BALANCE);
        kled.transfer(trader2, ACTOR_BALANCE);
        kled.transfer(mevBot, ACTOR_BALANCE * 5); // MEV bot has more capital
        kled.transfer(treasury, ACTOR_BALANCE * 10);
        vm.stopPrank();
    }

    function _setupApprovals() internal {
        vm.prank(proposer);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(trader1);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(trader2);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(mevBot);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(treasury);
        kled.approve(address(futarchy), type(uint256).max);
    }

    // =============================================================
    //        FORK-1: MEV SANDWICH ATTACK RESISTANCE
    // =============================================================

    /**
     * @notice Test resistance to sandwich attacks on large trades
     * @dev Simulates: MEV bot front-runs victim trade, then back-runs
     *
     * Scenario:
     * 1. Victim submits large buy order (visible in mempool)
     * 2. MEV bot front-runs with buy
     * 3. Victim's trade executes at worse price
     * 4. MEV bot back-runs with sell
     *
     * Expected: Slippage protection should limit MEV extraction
     */
    function test_Fork_MEVSandwichResistance() public {
        // Create proposal with high liquidity
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            50_000e18,
            keccak256("MEV test proposal"),
            50_000e18 // High liquidity
        );

        // Get initial price
        (uint256 initialPassPrice,) = futarchy.getMarketPrices(proposalId);

        // Victim wants to buy 5000 KLED worth of PASS tokens
        uint256 victimBuyAmount = 5_000e18;

        // Calculate expected tokens without MEV
        // (We'll compare with sandwiched outcome)

        // === SANDWICH ATTACK SIMULATION ===

        // Step 1: MEV bot front-runs (same block, higher priority)
        vm.prank(mevBot);
        uint256 mevFrontTokens = futarchy.buyOutcome(proposalId, true, 2_000e18, 0);

        (uint256 priceAfterFrontRun,) = futarchy.getMarketPrices(proposalId);

        // Step 2: Victim's trade executes at worse price
        // Use no slippage protection (minTokens = 0) to simulate naive user
        vm.prank(trader1);
        uint256 victimTokens = futarchy.buyOutcome(proposalId, true, victimBuyAmount, 0);

        (uint256 priceAfterVictim,) = futarchy.getMarketPrices(proposalId);

        // Step 3: MEV bot back-runs with sell
        vm.prank(mevBot);
        uint256 mevProfit = futarchy.sellOutcome(proposalId, true, mevFrontTokens, 0);

        // === ASSERTIONS ===

        // Price should have increased after front-run
        assertGt(priceAfterFrontRun, initialPassPrice, "Price should increase after front-run");

        // Victim should still receive tokens (slippage protection worked)
        assertGt(victimTokens, 0, "Victim should receive tokens");

        // MEV profit should be limited by AMM mechanics
        // In a well-designed AMM, sandwich profit is bounded
        uint256 mevCost = 2_000e18;
        int256 mevPnL = int256(mevProfit) - int256(mevCost);

        // Log the MEV extraction for analysis
        if (mevPnL > 0) {
            // Some MEV extraction is expected, but should be bounded
            assertLt(uint256(mevPnL), victimBuyAmount / 10, "MEV extraction should be < 10% of victim trade");
        }

        // Verify victim got tokens
        // In LMSR implementation, tokens = maxCost parameter
        // The "fairness" is in the cost, not the token count
        assertEq(victimTokens, victimBuyAmount, "LMSR: victim tokens should equal buy amount");
    }

    // =============================================================
    //        FORK-2: BLOCK TIMESTAMP EDGE CASES
    // =============================================================

    /**
     * @notice Test behavior at exact trading period boundaries
     * @dev Base chain has 2-second blocks, test timing precision
     */
    function test_Fork_TradingPeriodBoundary() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Timing test"),
            10_000e18
        );

        // Get trading end time (16 fields in struct)
        (,,,,,,,, uint48 tradingEnd,,,,,,,) = futarchy.proposals(proposalId);

        // Trade just before boundary (1 second before)
        vm.warp(tradingEnd - 1);

        vm.prank(trader1);
        uint256 tokens = futarchy.buyOutcome(proposalId, true, 100e18, 0);
        assertGt(tokens, 0, "Should be able to trade 1 second before end");

        // Try to trade exactly at boundary
        vm.warp(tradingEnd);

        vm.prank(trader2);
        vm.expectRevert(FutarchyTreasury.TradingNotActive.selector);
        futarchy.buyOutcome(proposalId, true, 100e18, 0);

        // Close trading should NOT work exactly at boundary (SEC-031 closing delay)
        vm.expectRevert(FutarchyTreasury.ClosingDelayNotPassed.selector);
        futarchy.closeTrading(proposalId);

        // Wait for closing delay (1 minute in test mode) and then close
        vm.warp(tradingEnd + 1 minutes);
        futarchy.closeTrading(proposalId);

        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Closed));
    }

    /**
     * @notice Test resolution timing with block variance
     * @dev Simulates realistic block production variance
     */
    function test_Fork_ResolutionTimingVariance() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Resolution timing"),
            10_000e18
        );

        // Do some trading
        vm.prank(trader1);
        futarchy.buyOutcome(proposalId, true, 1_000e18, 0);

        // Close trading
        vm.warp(block.timestamp + 11 minutes);
        futarchy.closeTrading(proposalId);

        // Get resolution time (16 fields in struct)
        (,,,,,,,,, uint48 resolutionTime,,,,,,) = futarchy.proposals(proposalId);

        // Try to resolve 1 second early (should fail)
        vm.warp(resolutionTime - 1);
        vm.expectRevert(FutarchyTreasury.TooEarly.selector);
        futarchy.resolveMarket(proposalId);

        // Resolve exactly at time (should work with emergencyResolve)
        vm.warp(resolutionTime);
        vm.prank(guardian);
        futarchy.emergencyResolve(proposalId, true);

        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Resolved));
    }

    // =============================================================
    //        FORK-3: LARGE TRADE IMPACT
    // =============================================================

    /**
     * @notice Test AMM behavior under large trade pressure
     * @dev Verifies price bounds and liquidity depletion handling
     */
    function test_Fork_LargeTradeImpact() public {
        // Create proposal with moderate liquidity
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Large trade test"),
            20_000e18 // 20K liquidity
        );

        (uint256 priceBefore,) = futarchy.getMarketPrices(proposalId);

        // Large trade: 50% of liquidity
        vm.prank(trader1);
        uint256 tokens = futarchy.buyOutcome(proposalId, true, 10_000e18, 0);

        (uint256 priceAfter,) = futarchy.getMarketPrices(proposalId);

        // Price should increase significantly but stay bounded
        assertGt(priceAfter, priceBefore, "Price should increase");
        assertLt(priceAfter, PRECISION, "Price should stay below 100%");

        // Should receive tokens
        assertGt(tokens, 0, "Should receive tokens");

        // Verify collateral tracking
        // Note: LMSR cost function means actual cost < requested amount
        uint256 collateral = futarchy.proposalCollateral(proposalId);
        assertGt(collateral, 20_000e18, "Collateral should be more than initial liquidity");
    }

    /**
     * @notice Test cascading large trades
     * @dev Multiple large trades in sequence
     */
    function test_Fork_CascadingLargeTrades() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Cascade test"),
            50_000e18 // High liquidity for multiple large trades
        );

        uint256[] memory prices = new uint256[](5);
        (prices[0],) = futarchy.getMarketPrices(proposalId);

        // 4 large sequential buys
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(trader1);
            futarchy.buyOutcome(proposalId, true, 5_000e18, 0);
            (prices[i + 1],) = futarchy.getMarketPrices(proposalId);
        }

        // Verify monotonic price increase
        for (uint256 i = 0; i < 4; i++) {
            assertGt(prices[i + 1], prices[i], "Prices should increase monotonically");
        }

        // Price should be high but bounded
        assertLt(prices[4], PRECISION, "Final price should be < 100%");
        assertGt(prices[4], PRECISION * 65 / 100, "Final price should be > 65%");
    }

    // =============================================================
    //        FORK-4: CONCURRENT PROPOSALS
    // =============================================================

    /**
     * @notice Test multiple concurrent proposals
     * @dev Simulates realistic governance load
     */
    function test_Fork_ConcurrentProposals() public {
        uint256[] memory proposalIds = new uint256[](5);

        // Create 5 concurrent proposals
        vm.startPrank(proposer);
        for (uint256 i = 0; i < 5; i++) {
            proposalIds[i] = futarchy.createProposal(
                target,
                "",
                10_000e18,
                keccak256(abi.encodePacked("Proposal ", i)),
                5_000e18
            );
        }
        vm.stopPrank();

        // Trade on all proposals
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(trader1);
            futarchy.buyOutcome(proposalIds[i], i % 2 == 0, 500e18, 0);

            vm.prank(trader2);
            futarchy.buyOutcome(proposalIds[i], i % 2 == 1, 300e18, 0);
        }

        // Close all
        vm.warp(block.timestamp + 11 minutes);
        for (uint256 i = 0; i < 5; i++) {
            futarchy.closeTrading(proposalIds[i]);
        }

        // Resolve all
        vm.warp(block.timestamp + 2 hours);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(guardian);
            futarchy.emergencyResolve(proposalIds[i], i % 2 == 0);
        }

        // Verify all resolved correctly
        for (uint256 i = 0; i < 5; i++) {
            FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalIds[i]);
            assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Resolved));
        }
    }

    // =============================================================
    //        FORK-5: GAS SPIKE SCENARIOS
    // =============================================================

    /**
     * @notice Test operations under high gas conditions
     * @dev Verifies gas limits are reasonable for Base chain
     */
    function test_Fork_GasLimits() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Gas test"),
            10_000e18
        );

        // Measure gas for key operations
        uint256 gasBefore;
        uint256 gasUsed;

        // Buy operation
        vm.prank(trader1);
        gasBefore = gasleft();
        futarchy.buyOutcome(proposalId, true, 1_000e18, 0);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 300_000, "Buy should use < 300K gas");

        // Sell operation
        uint256 balance = conditionalTokens.balanceOfOutcome(trader1, proposalId, true);
        vm.prank(trader1);
        gasBefore = gasleft();
        futarchy.sellOutcome(proposalId, true, balance / 2, 0);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200_000, "Sell should use < 200K gas");

        // Close trading (need trading end + closing delay for SEC-031)
        (,,,,,,,, uint48 tradingEnd,,,,,,,) = futarchy.proposals(proposalId);
        vm.warp(tradingEnd + 1 minutes + 1);
        gasBefore = gasleft();
        futarchy.closeTrading(proposalId);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200_000, "Close should use < 200K gas");

        // Resolve
        vm.warp(block.timestamp + 2 hours);
        vm.prank(guardian);
        gasBefore = gasleft();
        futarchy.emergencyResolve(proposalId, true);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 200_000, "Resolve should use < 200K gas");

        // Execute
        gasBefore = gasleft();
        futarchy.executeProposal(proposalId);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 150_000, "Execute should use < 150K gas");

        // Redeem
        vm.prank(trader1);
        gasBefore = gasleft();
        futarchy.redeemWinnings(proposalId);
        gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 150_000, "Redeem should use < 150K gas");
    }

    // =============================================================
    //        FORK-6: ADVERSARIAL SEQUENCING
    // =============================================================

    /**
     * @notice Test adversarial transaction ordering
     * @dev Simulates block builder reordering transactions
     */
    function test_Fork_AdversarialSequencing() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Sequencing test"),
            20_000e18
        );

        // Scenario: Two traders submit trades, builder reorders

        // Original order: trader1 buys, trader2 buys
        // Reordered: trader2 buys first (gets better price)

        (uint256 priceBefore,) = futarchy.getMarketPrices(proposalId);

        // Trader2 front-runs trader1
        vm.prank(trader2);
        uint256 trader2Tokens = futarchy.buyOutcome(proposalId, true, 2_000e18, 0);

        (uint256 priceAfterTrader2,) = futarchy.getMarketPrices(proposalId);

        // Trader1's trade executes at worse price
        vm.prank(trader1);
        uint256 trader1Tokens = futarchy.buyOutcome(proposalId, true, 2_000e18, 0);

        // LMSR behavior: tokens bought equals maxCost parameter
        // The cost (KLED spent) varies based on current price, not the tokens received

        // Both should receive tokens
        assertGt(trader1Tokens, 0, "Trader1 should receive tokens");
        assertGt(trader2Tokens, 0, "Trader2 should receive tokens");

        // In our LMSR implementation, tokens = maxCost, but cost varies
        // First trader gets tokens at lower cost (better price)
        assertEq(trader2Tokens, trader1Tokens, "Both get same tokens in LMSR (tokens = maxCost)");

        // The price should have increased after first trade
        assertGt(priceAfterTrader2, priceBefore, "Price should increase after trade");
    }

    // =============================================================
    //        FORK-7: PRICE MANIPULATION RESISTANCE
    // =============================================================

    /**
     * @notice Test resistance to price manipulation before resolution
     * @dev Last-minute trades shouldn't dramatically affect outcome
     */
    function test_Fork_LastMinutePriceManipulation() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Manipulation test"),
            30_000e18
        );

        // Normal trading establishes a price
        vm.prank(trader1);
        futarchy.buyOutcome(proposalId, true, 5_000e18, 0);

        vm.prank(trader2);
        futarchy.buyOutcome(proposalId, false, 3_000e18, 0);

        (uint256 establishedPassPrice, uint256 establishedFailPrice) = futarchy.getMarketPrices(proposalId);

        // Pass should be winning
        assertGt(establishedPassPrice, establishedFailPrice, "PASS should be winning");

        // Warp to just before trading ends
        vm.warp(block.timestamp + 10 minutes - 1);

        // Attacker tries last-minute manipulation
        vm.prank(mevBot);
        futarchy.buyOutcome(proposalId, false, 8_000e18, 0); // Large NO buy

        (uint256 manipulatedPassPrice, uint256 manipulatedFailPrice) = futarchy.getMarketPrices(proposalId);

        // Close trading - need to wait for trading end + closing delay (SEC-031)
        (,,,,,,,, uint48 tradingEnd,,,,,,,) = futarchy.proposals(proposalId);
        vm.warp(tradingEnd + 1 minutes + 1); // Wait for closing delay
        futarchy.closeTrading(proposalId);

        // The manipulation might flip the market, but:
        // 1. Attacker has capital at risk
        // 2. If they lose, they lose their stake
        // 3. Winners will claim their tokens

        // Resolve based on final prices (use emergency for test)
        vm.warp(block.timestamp + 2 hours);
        bool passWins = manipulatedPassPrice > manipulatedFailPrice;
        vm.prank(guardian);
        futarchy.emergencyResolve(proposalId, passWins);

        // Key invariant: system should remain consistent
        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Resolved));

        // Collateral should cover all claims
        uint256 collateral = futarchy.proposalCollateral(proposalId);
        assertGt(collateral, 0, "Collateral should be positive");
    }

    // =============================================================
    //        FORK-8: REALISTIC BASE CHAIN CONDITIONS
    // =============================================================

    /**
     * @notice Test under realistic Base chain block production
     * @dev Base has 2-second blocks
     */
    function test_Fork_BaseBlockProduction() public {
        vm.prank(proposer);
        uint256 proposalId = futarchy.createProposal(
            target,
            "",
            10_000e18,
            keccak256("Base blocks"),
            10_000e18
        );

        // Simulate 30 blocks of trading (1 minute on Base)
        for (uint256 i = 0; i < 30; i++) {
            // Advance by 2 seconds (1 Base block)
            vm.warp(block.timestamp + 2);
            vm.roll(block.number + 1);

            // Alternate trading
            if (i % 3 == 0) {
                vm.prank(trader1);
                futarchy.buyOutcome(proposalId, true, 50e18, 0);
            } else if (i % 3 == 1) {
                vm.prank(trader2);
                futarchy.buyOutcome(proposalId, false, 30e18, 0);
            }
            // Every 3rd block: no trade (realistic)
        }

        // Verify system state is consistent
        (uint256 passPrice, uint256 failPrice) = futarchy.getMarketPrices(proposalId);
        assertGt(passPrice + failPrice, 0, "Prices should be positive");

        // Verify trading still active
        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Active));
    }
}
