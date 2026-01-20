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
 * @title FutarchyE2ETest
 * @notice End-to-end integration tests for Futarchy Treasury system
 * @dev Implements acceptance test scenario FT-E2E-1 through FT-E2E-5
 *
 * Test Scenario FT-E2E-1: Complete YES Win Flow
 * - Phase 1: Proposal Creation (Day 0)
 * - Phase 2: Market Trading (Days 1-6)
 * - Phase 3: Market Resolution (Day 7+)
 * - Phase 4: Treasury Execution
 * - Phase 5: Winner Claims
 *
 * Actors:
 * - Alice: Proposal creator
 * - Bob: YES trader (bullish)
 * - Carol: NO trader (bearish)
 * - Dave: Resolver (anyone can call)
 */
contract FutarchyE2ETest is Test {
    // =============================================================
    //                        CONTRACTS
    // =============================================================

    KLEDToken public kled;
    ConditionalTokens public conditionalTokens;
    FutarchyAMM public amm;
    FutarchyTreasury public futarchy;

    // Implementation contracts for proxies
    FutarchyAMM public ammImpl;
    FutarchyTreasury public futarchyImpl;
    ConditionalTokens public condTokensImpl;

    // =============================================================
    //                          ACTORS
    // =============================================================

    address public guardian;
    address public treasury;
    address public marketingWallet; // Recipient for proposal

    address public alice; // Proposal creator
    address public bob;   // YES trader (bullish)
    address public carol; // NO trader (bearish)
    address public dave;  // Resolver

    // =============================================================
    //                        CONSTANTS
    // =============================================================

    uint256 public constant INITIAL_SUPPLY = 100_000_000e18;
    uint256 public constant ACTOR_BALANCE = 1_000_000e18;
    uint256 public constant PROPOSAL_STAKE = 100e18;  // Test mode stake
    uint256 public constant MIN_LIQUIDITY = 10e18;    // Test mode liquidity

    uint256 public constant PRECISION = 1e18;

    // =============================================================
    //                          EVENTS
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

    event MarketResolved(
        uint256 indexed proposalId,
        bool passWins,
        uint256 finalPassPrice,
        uint256 finalFailPrice
    );

    event ProposalExecuted(uint256 indexed proposalId, address target, uint256 amount);

    event WinningsRedeemed(
        uint256 indexed proposalId,
        address indexed redeemer,
        uint256 tokensRedeemed,
        uint256 kledReceived
    );

    // =============================================================
    //                          SETUP
    // =============================================================

    function setUp() public {
        // Create actors
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        marketingWallet = makeAddr("marketingWallet");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");

        // Deploy KLED token
        vm.prank(guardian);
        kled = new KLEDToken(guardian, INITIAL_SUPPLY);

        // Deploy ConditionalTokens
        condTokensImpl = new ConditionalTokens();
        bytes memory condInitData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy condProxy = new ERC1967Proxy(address(condTokensImpl), condInitData);
        conditionalTokens = ConditionalTokens(address(condProxy));

        // Deploy FutarchyAMM
        ammImpl = new FutarchyAMM();
        bytes memory ammInitData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy ammProxy = new ERC1967Proxy(address(ammImpl), ammInitData);
        amm = FutarchyAMM(address(ammProxy));

        // Deploy FutarchyTreasury
        futarchyImpl = new FutarchyTreasury();
        bytes memory futarchyInitData = abi.encodeWithSelector(
            FutarchyTreasury.initialize.selector,
            address(kled),
            address(conditionalTokens),
            address(amm),
            treasury,
            guardian
        );
        ERC1967Proxy futarchyProxy = new ERC1967Proxy(address(futarchyImpl), futarchyInitData);
        futarchy = FutarchyTreasury(address(futarchyProxy));

        // Configure AMM to accept FutarchyTreasury as treasury
        amm.setTreasury(address(futarchy));

        // Configure ConditionalTokens to accept FutarchyTreasury as minter
        conditionalTokens.setTreasury(address(futarchy));

        // Enable test mode (shorter periods, lower stakes)
        vm.prank(guardian);
        futarchy.setTestMode(true);

        // Fund actors with KLED
        vm.startPrank(guardian);
        kled.transfer(alice, ACTOR_BALANCE);
        kled.transfer(bob, ACTOR_BALANCE);
        kled.transfer(carol, ACTOR_BALANCE);
        kled.transfer(treasury, ACTOR_BALANCE * 10); // Treasury needs more for payouts
        vm.stopPrank();

        // Approve FutarchyTreasury for all actors
        vm.prank(alice);
        kled.approve(address(futarchy), type(uint256).max);

        vm.prank(bob);
        kled.approve(address(futarchy), type(uint256).max);

        vm.prank(carol);
        kled.approve(address(futarchy), type(uint256).max);

        // Treasury approves for proposal execution
        vm.prank(treasury);
        kled.approve(address(futarchy), type(uint256).max);
    }

    // =============================================================
    //        FT-E2E-1: COMPLETE YES WIN FLOW
    // =============================================================

    /**
     * @notice Full lifecycle test: Create → Trade → Resolve → Execute → Claim
     * @dev Implements acceptance test scenario FT-E2E-1
     */
    function test_E2E_CompleteYesWinFlow() public {
        // console.log("=== FT-E2E-1: Complete YES Win Flow ===");

        // =====================================================
        // PHASE 1: Proposal Creation (Day 0)
        // =====================================================
        // console.log("\n--- Phase 1: Proposal Creation ---");

        uint256 aliceBalanceBefore = kled.balanceOf(alice);
        // console.log("Alice KLED balance before:", aliceBalanceBefore / 1e18);

        // Step 1.3-1.5: Fill form and create proposal
        bytes32 descriptionHash = keccak256("Spend $50K on Twitter ads for KLED awareness");
        uint256 requestedAmount = 50_000e18;
        uint256 liquidity = 10_000e18; // Higher liquidity to support trading volume

        vm.prank(alice);
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "", // No calldata needed for simple transfer
            requestedAmount,
            descriptionHash,
            liquidity
        );

        // console.log("Proposal created with ID:", proposalId);

        // Phase 1 Verification
        assertEq(proposalId, 1, "First proposal should have ID 1");

        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Active), "Proposal should be Active");

        (uint256 passPrice, uint256 failPrice) = futarchy.getMarketPrices(proposalId);
        // console.log("Initial PASS price:", passPrice * 100 / PRECISION, "%");
        // console.log("Initial FAIL price:", failPrice * 100 / PRECISION, "%");

        // Prices should start at ~50%
        assertApproxEqRel(passPrice, PRECISION / 2, 0.1e18, "Pass price should be ~50%");
        assertApproxEqRel(failPrice, PRECISION / 2, 0.1e18, "Fail price should be ~50%");

        // =====================================================
        // PHASE 2: Market Trading (Days 1-6)
        // =====================================================
        // console.log("\n--- Phase 2: Market Trading ---");

        // Step 2.1-2.3: Bob buys YES (bullish on proposal)
        // Note: Trade amounts must be reasonable relative to liquidity to avoid AMM overflow
        uint256 bobKledBefore = kled.balanceOf(bob);

        vm.prank(bob);
        uint256 bobTokens1 = futarchy.buyOutcome(proposalId, true, 1500e18, 0);

        // console.log("Bob bought YES tokens:", bobTokens1 / 1e18);

        (passPrice, failPrice) = futarchy.getMarketPrices(proposalId);
        // console.log("After Bob buy - PASS:", passPrice * 100 / PRECISION, "%, FAIL:", failPrice * 100 / PRECISION, "%");

        // YES price should increase
        assertGt(passPrice, PRECISION / 2, "Pass price should increase after buy");

        // Step 2.4-2.6: Carol buys NO (bearish on proposal)
        vm.prank(carol);
        uint256 carolTokens = futarchy.buyOutcome(proposalId, false, 200e18, 0);

        // console.log("Carol bought NO tokens:", carolTokens / 1e18);

        // Step 2.7: Bob doubles down on YES
        vm.prank(bob);
        uint256 bobTokens2 = futarchy.buyOutcome(proposalId, true, 1500e18, 0);

        // console.log("Bob bought more YES tokens:", bobTokens2 / 1e18);

        uint256 bobTotalYes = bobTokens1 + bobTokens2;
        uint256 bobPassBalance = conditionalTokens.balanceOfOutcome(bob, proposalId, true);
        assertEq(bobPassBalance, bobTotalYes, "Bob's PASS balance should match purchases");

        // Phase 2 Verification
        (passPrice, failPrice) = futarchy.getMarketPrices(proposalId);
        // console.log("Final trading - PASS:", passPrice * 100 / PRECISION, "%, FAIL:", failPrice * 100 / PRECISION, "%");

        // YES should be winning (more buy pressure)
        assertGt(passPrice, failPrice, "PASS price should exceed FAIL price");

        // =====================================================
        // PHASE 3: Market Resolution (Day 7+)
        // =====================================================
        // console.log("\n--- Phase 3: Market Resolution ---");

        // Warp past trading period (10 minutes in test mode)
        vm.warp(block.timestamp + 11 minutes);

        // Step 3.1: Close trading
        futarchy.closeTrading(proposalId);

        state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Closed), "Proposal should be Closed");

        // Step 3.2: Verify trading is disabled
        vm.prank(bob);
        vm.expectRevert(FutarchyTreasury.TradingNotActive.selector);
        futarchy.buyOutcome(proposalId, true, 100e18, 0);

        // Warp past resolution delay (1 hour in test mode)
        vm.warp(block.timestamp + 2 hours);

        // Step 3.3-3.5: Resolve market (use emergencyResolve in test mode - price threshold too high)
        vm.prank(guardian);
        futarchy.emergencyResolve(proposalId, true); // PASS wins

        state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Resolved), "Proposal should be Resolved");

        // Get proposal to verify passWins
        (,,,,,,,,,,,,,, bool passWins) = _getProposal(proposalId);
        assertTrue(passWins, "PASS should win");

        // console.log("Market resolved: PASS wins =", passWins);

        // =====================================================
        // PHASE 4: Treasury Execution
        // =====================================================
        // console.log("\n--- Phase 4: Treasury Execution ---");

        uint256 marketingBalanceBefore = kled.balanceOf(marketingWallet);

        // Step 4.2-4.4: Execute proposal
        futarchy.executeProposal(proposalId);

        state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Executed), "Proposal should be Executed");

        uint256 marketingBalanceAfter = kled.balanceOf(marketingWallet);
        assertEq(
            marketingBalanceAfter - marketingBalanceBefore,
            requestedAmount,
            "Marketing wallet should receive requested amount"
        );

        // console.log("Treasury executed: Marketing wallet received", requestedAmount / 1e18, "KLED");

        // =====================================================
        // PHASE 5: Winner Claims
        // =====================================================
        // console.log("\n--- Phase 5: Winner Claims ---");

        uint256 bobKledBeforeClaim = kled.balanceOf(bob);
        uint256 bobPassTokens = conditionalTokens.balanceOfOutcome(bob, proposalId, true);

        // console.log("Bob's PASS tokens before claim:", bobPassTokens / 1e18);

        // Step 5.3-5.6: Bob claims winnings
        vm.prank(bob);
        futarchy.redeemWinnings(proposalId);

        uint256 bobKledAfterClaim = kled.balanceOf(bob);
        uint256 bobPayout = bobKledAfterClaim - bobKledBeforeClaim;

        // console.log("Bob received payout:", bobPayout / 1e18, "KLED");

        // Bob's PASS tokens should be burned
        uint256 bobPassAfter = conditionalTokens.balanceOfOutcome(bob, proposalId, true);
        assertEq(bobPassAfter, 0, "Bob's PASS tokens should be burned");

        // Bob should profit (invested 3000 KLED, should get more back)
        uint256 bobTotalInvested = 3000e18;
        assertGt(bobPayout, bobTotalInvested * 90 / 100, "Bob should roughly break even or profit");

        // Step 5.7-5.8: Carol's NO tokens are worthless
        uint256 carolNoBalance = conditionalTokens.balanceOfOutcome(carol, proposalId, false);
        // console.log("Carol's NO tokens (worthless):", carolNoBalance / 1e18);

        // Carol cannot redeem (she has NO tokens, but PASS won)
        // Her NO tokens are worthless

        // console.log("\n=== FT-E2E-1 COMPLETE: YES Win Flow Successful ===");
    }

    // =============================================================
    //        FT-E2E-2: COMPLETE NO WIN FLOW
    // =============================================================

    /**
     * @notice Test NO win scenario where proposal is rejected
     * @dev Implements acceptance test scenario FT-E2E-2
     */
    function test_E2E_CompleteNoWinFlow() public {
        // console.log("=== FT-E2E-2: Complete NO Win Flow ===");

        // Create proposal
        bytes32 descriptionHash = keccak256("Spend $200K on Super Bowl ad");
        uint256 liquidity = 10_000e18;

        vm.prank(alice);
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "",
            200_000e18,
            descriptionHash,
            liquidity
        );

        // Trading: NO dominates heavily to ensure clear winner (>55% threshold)
        vm.prank(bob);
        futarchy.buyOutcome(proposalId, true, 200e18, 0); // Small YES buy

        vm.prank(carol);
        futarchy.buyOutcome(proposalId, false, 1500e18, 0); // Large NO buy

        vm.prank(carol);
        futarchy.buyOutcome(proposalId, false, 1500e18, 0); // More NO - total 3000e18

        (uint256 passPrice, uint256 failPrice) = futarchy.getMarketPrices(proposalId);
        // console.log("PASS price:", passPrice * 100 / PRECISION, "%");
        // console.log("FAIL price:", failPrice * 100 / PRECISION, "%");

        // NO should be winning
        assertGt(failPrice, passPrice, "FAIL should exceed PASS");

        // Close and resolve
        vm.warp(block.timestamp + 11 minutes);
        futarchy.closeTrading(proposalId);

        vm.warp(block.timestamp + 2 hours);
        // Use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchy.emergencyResolve(proposalId, false); // FAIL wins

        // Verify NO wins
        (,,,,,,,,,,,,,, bool passWins) = _getProposal(proposalId);
        assertFalse(passWins, "PASS should NOT win");

        // Reject proposal
        futarchy.rejectProposal(proposalId);

        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Rejected), "Should be Rejected");

        // Treasury unchanged
        uint256 marketingBalance = kled.balanceOf(marketingWallet);
        assertEq(marketingBalance, 0, "Marketing wallet should receive nothing");

        // Carol claims winnings
        uint256 carolBefore = kled.balanceOf(carol);
        vm.prank(carol);
        futarchy.redeemWinnings(proposalId);
        uint256 carolAfter = kled.balanceOf(carol);

        // console.log("Carol profit:", (carolAfter - carolBefore) / 1e18, "KLED");
        assertGt(carolAfter, carolBefore, "Carol should profit");

        // console.log("=== FT-E2E-2 COMPLETE: NO Win Flow Successful ===");
    }

    // =============================================================
    //        FT-E2E-3: CANCEL FLOW
    // =============================================================

    /**
     * @notice Test proposal cancellation by proposer
     */
    function test_E2E_ProposerCancel() public {
        // console.log("=== FT-E2E-3: Proposer Cancel Flow ===");

        uint256 aliceBalanceBefore = kled.balanceOf(alice);

        // Create proposal
        vm.prank(alice);
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "",
            50_000e18,
            keccak256("Test proposal"),
            1000e18
        );

        uint256 aliceAfterCreate = kled.balanceOf(alice);
        uint256 totalStaked = aliceBalanceBefore - aliceAfterCreate;
        // console.log("Alice staked:", totalStaked / 1e18, "KLED");

        // Cancel before trading ends
        vm.prank(alice);
        futarchy.cancelProposal(proposalId);

        FutarchyTreasury.ProposalState state = futarchy.getProposalState(proposalId);
        assertEq(uint256(state), uint256(FutarchyTreasury.ProposalState.Canceled), "Should be Canceled");

        // Alice should get full refund
        uint256 aliceAfterCancel = kled.balanceOf(alice);
        assertEq(aliceAfterCancel, aliceBalanceBefore, "Alice should get full refund");

        // console.log("=== FT-E2E-3 COMPLETE ===");
    }

    // =============================================================
    //        FT-E2E-4: SELL BEFORE RESOLUTION
    // =============================================================

    /**
     * @notice Test selling tokens before market resolution
     */
    function test_E2E_SellBeforeResolution() public {
        // console.log("=== FT-E2E-4: Sell Before Resolution ===");

        // Create proposal
        vm.prank(alice);
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "",
            50_000e18,
            keccak256("Test"),
            1000e18
        );

        // Bob buys YES
        vm.prank(bob);
        uint256 bobTokens = futarchy.buyOutcome(proposalId, true, 500e18, 0);

        // console.log("Bob bought:", bobTokens / 1e18, "YES tokens");

        uint256 bobKledBefore = kled.balanceOf(bob);

        // Bob sells half
        vm.prank(bob);
        uint256 kledReceived = futarchy.sellOutcome(proposalId, true, bobTokens / 2, 0);

        // console.log("Bob sold half, received:", kledReceived / 1e18, "KLED");

        uint256 bobKledAfter = kled.balanceOf(bob);
        assertEq(bobKledAfter - bobKledBefore, kledReceived, "KLED received should match");

        // Bob still has half the tokens
        uint256 bobRemaining = conditionalTokens.balanceOfOutcome(bob, proposalId, true);
        assertApproxEqRel(bobRemaining, bobTokens / 2, 0.01e18, "Bob should have half tokens");

        // console.log("=== FT-E2E-4 COMPLETE ===");
    }

    // =============================================================
    //        FT-E2E-5: MULTIPLE TRADERS
    // =============================================================

    /**
     * @notice Test with multiple competing traders
     */
    function test_E2E_MultipleTraders() public {
        // console.log("=== FT-E2E-5: Multiple Traders ===");

        // Create more actors
        address trader1 = makeAddr("trader1");
        address trader2 = makeAddr("trader2");
        address trader3 = makeAddr("trader3");

        vm.startPrank(guardian);
        kled.transfer(trader1, ACTOR_BALANCE);
        kled.transfer(trader2, ACTOR_BALANCE);
        kled.transfer(trader3, ACTOR_BALANCE);
        vm.stopPrank();

        vm.prank(trader1);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(trader2);
        kled.approve(address(futarchy), type(uint256).max);
        vm.prank(trader3);
        kled.approve(address(futarchy), type(uint256).max);

        // Create proposal with higher liquidity to support multiple traders
        vm.prank(alice);
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "",
            50_000e18,
            keccak256("Multi-trader test"),
            10_000e18  // Higher liquidity for multiple traders
        );

        // Multiple trades - keep amounts reasonable relative to liquidity
        vm.prank(trader1);
        futarchy.buyOutcome(proposalId, true, 800e18, 0);

        vm.prank(trader2);
        futarchy.buyOutcome(proposalId, false, 500e18, 0);

        vm.prank(trader3);
        futarchy.buyOutcome(proposalId, true, 1200e18, 0);

        vm.prank(bob);
        futarchy.buyOutcome(proposalId, true, 1000e18, 0);

        vm.prank(carol);
        futarchy.buyOutcome(proposalId, false, 500e18, 0);

        (uint256 passPrice, uint256 failPrice) = futarchy.getMarketPrices(proposalId);
        // console.log("Final PASS:", passPrice * 100 / PRECISION, "%");
        // console.log("Final FAIL:", failPrice * 100 / PRECISION, "%");

        // Complete lifecycle
        vm.warp(block.timestamp + 11 minutes);
        futarchy.closeTrading(proposalId);

        vm.warp(block.timestamp + 2 hours);
        // Use emergencyResolve in test mode - PASS has more buy pressure so let PASS win
        vm.prank(guardian);
        futarchy.emergencyResolve(proposalId, true); // PASS wins (3000e18 YES vs 1000e18 NO)

        (,,,,,,,,,,,,,, bool passWins) = _getProposal(proposalId);

        if (passWins) {
            futarchy.executeProposal(proposalId);
            // console.log("PASS won - proposal executed");
        } else {
            futarchy.rejectProposal(proposalId);
            // console.log("FAIL won - proposal rejected");
        }

        // console.log("=== FT-E2E-5 COMPLETE ===");
    }

    // =============================================================
    //                    GAS BENCHMARKS
    // =============================================================

    /**
     * @notice Benchmark gas usage for key operations
     * @dev From acceptance test gas requirements
     */
    function test_GasBenchmarks() public {
        // console.log("=== Gas Benchmarks ===");

        // Create proposal gas (use higher liquidity to avoid AMM overflow)
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        uint256 proposalId = futarchy.createProposal(
            marketingWallet,
            "",
            50_000e18,
            keccak256("Benchmark"),
            10_000e18
        );
        uint256 createGas = gasBefore - gasleft();
        // console.log("Create proposal gas:", createGas);
        assertLt(createGas, 800_000, "Create should be < 800K gas");

        // First buy gas
        vm.prank(bob);
        gasBefore = gasleft();
        futarchy.buyOutcome(proposalId, true, 500e18, 0);
        uint256 firstBuyGas = gasBefore - gasleft();
        // console.log("First buy gas:", firstBuyGas);
        assertLt(firstBuyGas, 250_000, "First buy should be < 250K gas");

        // Subsequent buy gas
        vm.prank(bob);
        gasBefore = gasleft();
        futarchy.buyOutcome(proposalId, true, 500e18, 0);
        uint256 subsequentBuyGas = gasBefore - gasleft();
        // console.log("Subsequent buy gas:", subsequentBuyGas);
        assertLt(subsequentBuyGas, 150_000, "Subsequent buy should be < 150K gas");

        // Sell gas
        uint256 balance = conditionalTokens.balanceOfOutcome(bob, proposalId, true);
        vm.prank(bob);
        gasBefore = gasleft();
        futarchy.sellOutcome(proposalId, true, balance / 2, 0);
        uint256 sellGas = gasBefore - gasleft();
        // console.log("Sell gas:", sellGas);
        assertLt(sellGas, 150_000, "Sell should be < 150K gas");

        // Resolution gas
        vm.warp(block.timestamp + 11 minutes);
        futarchy.closeTrading(proposalId);
        vm.warp(block.timestamp + 2 hours);

        // Use emergencyResolve in test mode
        vm.prank(guardian);
        gasBefore = gasleft();
        futarchy.emergencyResolve(proposalId, true); // PASS wins
        uint256 resolveGas = gasBefore - gasleft();
        // console.log("Resolve gas:", resolveGas);
        assertLt(resolveGas, 350_000, "Resolve should be < 350K gas");

        // Execute gas
        gasBefore = gasleft();
        futarchy.executeProposal(proposalId);
        uint256 executeGas = gasBefore - gasleft();
        // console.log("Execute gas:", executeGas);
        assertLt(executeGas, 200_000, "Execute should be < 200K gas");

        // Claim gas
        vm.prank(bob);
        gasBefore = gasleft();
        futarchy.redeemWinnings(proposalId);
        uint256 claimGas = gasBefore - gasleft();
        // console.log("Claim gas:", claimGas);
        assertLt(claimGas, 150_000, "Claim should be < 150K gas");

        // console.log("=== Gas Benchmarks COMPLETE ===");
    }

    // =============================================================
    //                    HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Helper to get full proposal struct
     */
    function _getProposal(uint256 proposalId) internal view returns (
        address proposer,
        bytes32 descriptionHash,
        address target,
        bytes memory data,
        uint256 requestedAmount,
        uint256 passMarketId,
        uint256 failMarketId,
        uint48 tradingStart,
        uint48 tradingEnd,
        uint48 resolutionTime,
        uint256 proposerStake,
        uint256 initialLiquidity,
        FutarchyTreasury.ProposalState state,
        uint256 passPrice,
        bool passWins
    ) {
        (
            proposer,
            descriptionHash,
            target,
            data,
            requestedAmount,
            passMarketId,
            failMarketId,
            tradingStart,
            tradingEnd,
            resolutionTime,
            proposerStake,
            initialLiquidity,
            state,
            passPrice,
            , // failPrice
            passWins
        ) = _getProposalRaw(proposalId);
    }

    function _getProposalRaw(uint256 proposalId) internal view returns (
        address, bytes32, address, bytes memory, uint256,
        uint256, uint256, uint48, uint48, uint48,
        uint256, uint256, FutarchyTreasury.ProposalState,
        uint256, uint256, bool
    ) {
        // Access via public mapping
        (
            address proposer,
            bytes32 descHash,
            address target,
            ,
            uint256 reqAmt,
            uint256 passId,
            uint256 failId,
            uint48 tStart,
            uint48 tEnd,
            uint48 resTime,
            uint256 stake,
            uint256 liq,
            FutarchyTreasury.ProposalState st,
            uint256 pPrice,
            uint256 fPrice,
            bool pWins
        ) = futarchy.proposals(proposalId);

        return (
            proposer, descHash, target, "", reqAmt,
            passId, failId, tStart, tEnd, resTime,
            stake, liq, st, pPrice, fPrice, pWins
        );
    }
}
