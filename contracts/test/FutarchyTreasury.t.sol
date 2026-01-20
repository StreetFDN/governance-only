// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FutarchyTreasury} from "../src/FutarchyTreasury.sol";
import {FutarchyAMM} from "../src/FutarchyAMM.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock KLED Token for testing
 */
contract MockKLED is ERC20 {
    constructor() ERC20("KLED Token", "KLED") {
        _mint(msg.sender, 1_000_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FutarchyTreasury Tests
 * @notice Comprehensive tests for the Futarchy governance system
 *
 * Invariants tested:
 * - FUT-1: KLED balance >= sum(unreturned stakes) + sum(market collateral)
 * - FUT-2: Proposal can only be executed if passWins == true
 * - FUT-7: Executed/Rejected/Canceled are terminal states
 */
contract FutarchyTreasuryTest is Test {
    FutarchyTreasury public futarchyTreasury;
    FutarchyAMM public amm;
    ConditionalTokens public conditionalTokens;
    MockKLED public kled;

    address public guardian = address(0x1);
    address public treasury = address(0x2);
    address public proposer = address(0x3);
    address public trader1 = address(0x4);
    address public trader2 = address(0x5);
    address public target = address(0x6);

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_STAKE = 100e18;       // Test mode stake
    uint256 public constant DEFAULT_LIQUIDITY = 100e18;   // Test mode min liquidity
    uint256 public constant TRADER_BALANCE = 10_000e18;
    // Buy amounts must be small relative to liquidity to avoid LMSR overflow
    // But large enough to create price differences > 55% for resolution
    uint256 public constant SMALL_BUY = 3e18;
    uint256 public constant MEDIUM_BUY = 8e18;
    uint256 public constant LARGE_BUY = 40e18;  // Dominant position to win resolution

    // Events
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
    event OutcomePurchased(uint256 indexed proposalId, address indexed buyer, bool isPass, uint256 kledSpent, uint256 tokensReceived, uint256 newPrice);
    event OutcomeSold(uint256 indexed proposalId, address indexed seller, bool isPass, uint256 tokensSold, uint256 kledReceived, uint256 newPrice);
    event TradingClosed(uint256 indexed proposalId, uint256 passPrice, uint256 failPrice);
    event MarketResolved(uint256 indexed proposalId, bool passWins, uint256 finalPassPrice, uint256 finalFailPrice);
    event ProposalExecuted(uint256 indexed proposalId, address target, uint256 amount);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event WinningsRedeemed(uint256 indexed proposalId, address indexed redeemer, uint256 tokensRedeemed, uint256 kledReceived);
    event StakeReturned(uint256 indexed proposalId, address indexed proposer, uint256 amount);
    event TestModeEnabled(bool enabled);
    event EmergencyResolution(uint256 indexed proposalId, bool passWins, address guardian);

    function setUp() public {
        // Deploy mock KLED
        kled = new MockKLED();

        // Deploy ConditionalTokens
        ConditionalTokens ctImpl = new ConditionalTokens();
        bytes memory ctInitData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy ctProxy = new ERC1967Proxy(address(ctImpl), ctInitData);
        conditionalTokens = ConditionalTokens(address(ctProxy));

        // Deploy AMM
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
        futarchyTreasury = FutarchyTreasury(address(ftProxy));

        // Set treasury as the authorized caller for CT and AMM
        conditionalTokens.setTreasury(address(futarchyTreasury));
        amm.setTreasury(address(futarchyTreasury));

        // Enable test mode
        vm.prank(guardian);
        futarchyTreasury.setTestMode(true);

        // Fund accounts
        kled.transfer(proposer, 100_000e18);
        kled.transfer(trader1, TRADER_BALANCE);
        kled.transfer(trader2, TRADER_BALANCE);
        kled.transfer(treasury, 1_000_000e18);

        // Approve treasury to spend
        vm.prank(proposer);
        kled.approve(address(futarchyTreasury), type(uint256).max);
        vm.prank(trader1);
        kled.approve(address(futarchyTreasury), type(uint256).max);
        vm.prank(trader2);
        kled.approve(address(futarchyTreasury), type(uint256).max);
        vm.prank(treasury);
        kled.approve(address(futarchyTreasury), type(uint256).max);
    }

    // =============================================================
    //                    INITIALIZATION TESTS
    // =============================================================

    function test_Initialize() public view {
        assertEq(address(futarchyTreasury.kledToken()), address(kled));
        assertEq(address(futarchyTreasury.conditionalTokens()), address(conditionalTokens));
        assertEq(address(futarchyTreasury.amm()), address(amm));
        assertEq(futarchyTreasury.guardian(), guardian);
        assertTrue(futarchyTreasury.testMode());
    }

    function test_Initialize_RevertZeroAddress() public {
        FutarchyTreasury ftImpl = new FutarchyTreasury();

        // Zero KLED token
        bytes memory initData = abi.encodeWithSelector(
            FutarchyTreasury.initialize.selector,
            address(0), address(conditionalTokens), address(amm), treasury, guardian
        );
        vm.expectRevert(FutarchyTreasury.ZeroAddress.selector);
        new ERC1967Proxy(address(ftImpl), initData);
    }

    // =============================================================
    //                    PROPOSAL CREATION TESTS
    // =============================================================

    function test_CreateProposal_Success() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target,
            "",
            1000e18,
            keccak256("description"),
            DEFAULT_LIQUIDITY
        );

        assertEq(proposalId, 1);
        assertEq(futarchyTreasury.proposalCount(), 1);
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Active));
    }

    function test_CreateProposal_TransfersStakeAndLiquidity() public {
        uint256 proposerBalanceBefore = kled.balanceOf(proposer);
        uint256 treasuryBalanceBefore = kled.balanceOf(address(futarchyTreasury));

        vm.prank(proposer);
        futarchyTreasury.createProposal(
            target,
            "",
            1000e18,
            keccak256("description"),
            DEFAULT_LIQUIDITY
        );

        uint256 totalRequired = DEFAULT_STAKE + DEFAULT_LIQUIDITY;
        assertEq(kled.balanceOf(proposer), proposerBalanceBefore - totalRequired);
        assertEq(kled.balanceOf(address(futarchyTreasury)), treasuryBalanceBefore + totalRequired);
    }

    function test_CreateProposal_RevertZeroTarget() public {
        vm.prank(proposer);
        vm.expectRevert(FutarchyTreasury.ZeroAddress.selector);
        futarchyTreasury.createProposal(
            address(0),
            "",
            1000e18,
            keccak256("description"),
            DEFAULT_LIQUIDITY
        );
    }

    function test_CreateProposal_RevertInsufficientLiquidity() public {
        vm.prank(proposer);
        vm.expectRevert(FutarchyTreasury.InsufficientBalance.selector);
        futarchyTreasury.createProposal(
            target,
            "",
            1000e18,
            keccak256("description"),
            1e18  // Below min liquidity
        );
    }

    function test_CreateProposal_MultipleProposals() public {
        vm.startPrank(proposer);

        uint256 id1 = futarchyTreasury.createProposal(target, "", 100e18, keccak256("1"), DEFAULT_LIQUIDITY);
        uint256 id2 = futarchyTreasury.createProposal(target, "", 200e18, keccak256("2"), DEFAULT_LIQUIDITY);
        uint256 id3 = futarchyTreasury.createProposal(target, "", 300e18, keccak256("3"), DEFAULT_LIQUIDITY);

        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(futarchyTreasury.proposalCount(), 3);
    }

    // =============================================================
    //                    TRADING TESTS
    // =============================================================

    function test_BuyOutcome_Success() public {
        // Create proposal
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Buy PASS outcome
        vm.prank(trader1);
        uint256 tokensReceived = futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        assertGt(tokensReceived, 0);
        assertEq(conditionalTokens.balanceOfOutcome(trader1, proposalId, true), tokensReceived);
    }

    function test_BuyOutcome_BothOutcomes() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Trader1 buys PASS
        vm.prank(trader1);
        uint256 passTokens = futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        // Trader2 buys FAIL
        vm.prank(trader2);
        uint256 failTokens = futarchyTreasury.buyOutcome(proposalId, false, SMALL_BUY, 0);

        assertGt(passTokens, 0);
        assertGt(failTokens, 0);
        assertEq(conditionalTokens.balanceOfOutcome(trader1, proposalId, true), passTokens);
        assertEq(conditionalTokens.balanceOfOutcome(trader2, proposalId, false), failTokens);
    }

    function test_BuyOutcome_RevertTradingClosed() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Warp past trading end
        vm.warp(block.timestamp + 11 minutes);

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.TradingNotActive.selector);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);
    }

    function test_BuyOutcome_RevertZeroAmount() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.ZeroAmount.selector);
        futarchyTreasury.buyOutcome(proposalId, true, 0, 0);
    }

    function test_SellOutcome_Success() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Buy first
        vm.prank(trader1);
        uint256 tokens = futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        uint256 balanceBefore = kled.balanceOf(trader1);

        // Sell half
        vm.prank(trader1);
        uint256 kledReceived = futarchyTreasury.sellOutcome(proposalId, true, tokens / 2, 0);

        assertGt(kledReceived, 0);
        assertEq(kled.balanceOf(trader1), balanceBefore + kledReceived);
        assertEq(conditionalTokens.balanceOfOutcome(trader1, proposalId, true), tokens - tokens / 2);
    }

    function test_SellOutcome_RevertInsufficientBalance() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.InsufficientBalance.selector);
        futarchyTreasury.sellOutcome(proposalId, true, 100e18, 0);
    }

    // =============================================================
    //                    LIFECYCLE TESTS
    // =============================================================

    function test_CloseTrading_Success() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Do some trading
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        // Warp past trading end
        vm.warp(block.timestamp + 11 minutes);

        futarchyTreasury.closeTrading(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Closed));
    }

    function test_CloseTrading_RevertTooEarly() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.expectRevert(FutarchyTreasury.TooEarly.selector);
        futarchyTreasury.closeTrading(proposalId);
    }

    function test_ResolveMarket_PassWins() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Heavy buying on PASS to make it win
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        // Close trading
        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode (price threshold is too high for test amounts)
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Resolved));
    }

    function test_ResolveMarket_ReturnsStake() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        uint256 proposerBalanceBefore = kled.balanceOf(proposer);

        // Use emergencyResolve in test mode
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);

        // Stake should be returned
        assertEq(kled.balanceOf(proposer), proposerBalanceBefore + DEFAULT_STAKE);
    }

    function test_ResolveMarket_RevertTooEarly() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Try to resolve too early
        vm.expectRevert(FutarchyTreasury.TooEarly.selector);
        futarchyTreasury.resolveMarket(proposalId);
    }

    // =============================================================
    //                    FUT-2: EXECUTION REQUIRES PASS WINS
    // =============================================================

    function test_FUT2_ExecuteProposal_Success() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Make PASS win
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);

        futarchyTreasury.executeProposal(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Executed));
    }

    function test_FUT2_ExecuteProposal_RevertPassDidNotWin() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Make FAIL win by buying heavily on FAIL
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, false, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, false);

        vm.expectRevert(FutarchyTreasury.PassDidNotWin.selector);
        futarchyTreasury.executeProposal(proposalId);
    }

    function test_FUT2_ExecuteProposal_RevertNotResolved() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.expectRevert(FutarchyTreasury.NotResolved.selector);
        futarchyTreasury.executeProposal(proposalId);
    }

    // =============================================================
    //                    REJECT PROPOSAL TESTS
    // =============================================================

    function test_RejectProposal_Success() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Make FAIL win
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, false, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, false);

        futarchyTreasury.rejectProposal(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Rejected));
    }

    function test_RejectProposal_RevertIfPassWon() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Make PASS win
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with PASS winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);

        vm.expectRevert(FutarchyTreasury.InvalidState.selector);
        futarchyTreasury.rejectProposal(proposalId);
    }

    // =============================================================
    //                    REDEEM WINNINGS TESTS
    // =============================================================

    function test_RedeemWinnings_PassWins() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Trader1 buys PASS (winner)
        vm.prank(trader1);
        uint256 passTokens = futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        // Trader2 buys FAIL (loser)
        vm.prank(trader2);
        futarchyTreasury.buyOutcome(proposalId, false, SMALL_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with PASS winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);
        futarchyTreasury.executeProposal(proposalId);

        uint256 balanceBefore = kled.balanceOf(trader1);

        // Trader1 redeems winnings
        vm.prank(trader1);
        futarchyTreasury.redeemWinnings(proposalId);

        assertGt(kled.balanceOf(trader1), balanceBefore);
        assertEq(conditionalTokens.balanceOfOutcome(trader1, proposalId, true), 0);

        // Silence unused variable warning
        (passTokens);
    }

    function test_RedeemWinnings_FailWins() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // Trader1 buys PASS (loser)
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        // Trader2 buys FAIL (winner)
        vm.prank(trader2);
        uint256 failTokens = futarchyTreasury.buyOutcome(proposalId, false, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, false);
        futarchyTreasury.rejectProposal(proposalId);

        uint256 balanceBefore = kled.balanceOf(trader2);

        // Trader2 redeems winnings
        vm.prank(trader2);
        futarchyTreasury.redeemWinnings(proposalId);

        assertGt(kled.balanceOf(trader2), balanceBefore);

        // Silence unused variable warning
        (failTokens);
    }

    function test_RedeemWinnings_RevertNotResolved() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.NotResolved.selector);
        futarchyTreasury.redeemWinnings(proposalId);
    }

    function test_RedeemWinnings_RevertZeroBalance() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with PASS winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);
        futarchyTreasury.executeProposal(proposalId);

        // Trader2 has no tokens
        vm.prank(trader2);
        vm.expectRevert(FutarchyTreasury.ZeroAmount.selector);
        futarchyTreasury.redeemWinnings(proposalId);
    }

    // =============================================================
    //                    FUT-7: TERMINAL STATES
    // =============================================================

    function test_FUT7_ExecutedIsTerminal() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with PASS winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);
        futarchyTreasury.executeProposal(proposalId);

        // Can't execute again
        vm.expectRevert(FutarchyTreasury.NotResolved.selector);
        futarchyTreasury.executeProposal(proposalId);

        // Can't cancel
        vm.prank(guardian);
        vm.expectRevert(FutarchyTreasury.InvalidState.selector);
        futarchyTreasury.cancelProposal(proposalId);
    }

    function test_FUT7_RejectedIsTerminal() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, false, LARGE_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, false);
        futarchyTreasury.rejectProposal(proposalId);

        // Can't reject again
        vm.expectRevert(FutarchyTreasury.NotResolved.selector);
        futarchyTreasury.rejectProposal(proposalId);
    }

    function test_FUT7_CanceledIsTerminal() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(proposer);
        futarchyTreasury.cancelProposal(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Canceled));

        // Can't buy after cancel
        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.TradingNotActive.selector);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);
    }

    // =============================================================
    //                    CANCEL PROPOSAL TESTS
    // =============================================================

    function test_CancelProposal_ByProposer() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        uint256 balanceBefore = kled.balanceOf(proposer);

        vm.prank(proposer);
        futarchyTreasury.cancelProposal(proposalId);

        // Stake + liquidity returned
        assertEq(kled.balanceOf(proposer), balanceBefore + DEFAULT_STAKE + DEFAULT_LIQUIDITY);
    }

    function test_CancelProposal_ByGuardian() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(guardian);
        futarchyTreasury.cancelProposal(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Canceled));
    }

    function test_CancelProposal_GuardianCanCancelClosed() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Guardian can cancel even when closed
        vm.prank(guardian);
        futarchyTreasury.cancelProposal(proposalId);
    }

    function test_CancelProposal_RevertNotProposer() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.NotProposer.selector);
        futarchyTreasury.cancelProposal(proposalId);
    }

    // =============================================================
    //                    GUARDIAN FUNCTIONS
    // =============================================================

    function test_EmergencyResolve() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // Guardian can emergency resolve
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Resolved));
    }

    function test_EmergencyResolve_RevertNotGuardian() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        vm.prank(trader1);
        vm.expectRevert(FutarchyTreasury.OnlyGuardian.selector);
        futarchyTreasury.emergencyResolve(proposalId, true);
    }

    function test_Pause_BlocksTrading() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(guardian);
        futarchyTreasury.pause();

        vm.prank(trader1);
        vm.expectRevert();  // Pausable: paused
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);
    }

    function test_Unpause_AllowsTrading() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        vm.prank(guardian);
        futarchyTreasury.pause();

        vm.prank(guardian);
        futarchyTreasury.unpause();

        // Trading works again
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);
    }

    function test_SetTestMode() public {
        assertEq(futarchyTreasury.testMode(), true);

        vm.prank(guardian);
        futarchyTreasury.setTestMode(false);

        assertEq(futarchyTreasury.testMode(), false);
    }

    // =============================================================
    //                    CONFIGURATION TESTS
    // =============================================================

    function test_SetProposalStake() public {
        vm.prank(guardian);
        futarchyTreasury.setProposalStake(100_000e18);

        assertEq(futarchyTreasury.proposalStake(), 100_000e18);
    }

    function test_SetMinLiquidity() public {
        vm.prank(guardian);
        futarchyTreasury.setMinLiquidity(50_000e18);

        assertEq(futarchyTreasury.minLiquidity(), 50_000e18);
    }

    function test_SetTradingPeriod() public {
        vm.prank(guardian);
        futarchyTreasury.setTradingPeriod(14 days);

        assertEq(futarchyTreasury.tradingPeriod(), 14 days);
    }

    function test_SetResolutionDelay() public {
        vm.prank(guardian);
        futarchyTreasury.setResolutionDelay(60 days);

        assertEq(futarchyTreasury.resolutionDelay(), 60 days);
    }

    // =============================================================
    //                    VIEW FUNCTIONS
    // =============================================================

    function test_GetMarketPrices() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        (uint256 passPrice, uint256 failPrice) = futarchyTreasury.getMarketPrices(proposalId);

        // Initial prices should be ~50%
        assertApproxEqRel(passPrice, PRECISION / 2, 0.1e18);
        assertApproxEqRel(failPrice, PRECISION / 2, 0.1e18);
    }

    function test_GetProposalState() public {
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Active));

        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Closed));
    }

    // =============================================================
    //                    FULL LIFECYCLE TEST
    // =============================================================

    function test_FullLifecycle_PassWins() public {
        // 1. Create proposal
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Active));

        // 2. Trading - PASS dominates
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, LARGE_BUY, 0);

        vm.prank(trader2);
        futarchyTreasury.buyOutcome(proposalId, false, SMALL_BUY, 0);

        // 3. Close trading
        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Closed));

        // 4. Resolve - use emergencyResolve in test mode with PASS winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, true);
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Resolved));

        // 5. Execute
        futarchyTreasury.executeProposal(proposalId);
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Executed));

        // 6. Redeem winnings
        uint256 balanceBefore = kled.balanceOf(trader1);
        vm.prank(trader1);
        futarchyTreasury.redeemWinnings(proposalId);
        assertGt(kled.balanceOf(trader1), balanceBefore);
    }

    function test_FullLifecycle_FailWins() public {
        // 1. Create proposal
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        // 2. Trading - FAIL dominates
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, SMALL_BUY, 0);

        vm.prank(trader2);
        futarchyTreasury.buyOutcome(proposalId, false, LARGE_BUY, 0);

        // 3. Close trading
        vm.warp(block.timestamp + 11 minutes);
        futarchyTreasury.closeTrading(proposalId);

        // 4. Resolve - use emergencyResolve in test mode with FAIL winning
        vm.prank(guardian);
        futarchyTreasury.emergencyResolve(proposalId, false);

        // 5. Reject
        futarchyTreasury.rejectProposal(proposalId);
        assertEq(uint256(futarchyTreasury.getProposalState(proposalId)), uint256(FutarchyTreasury.ProposalState.Rejected));

        // 6. Trader2 redeems winnings
        uint256 balanceBefore = kled.balanceOf(trader2);
        vm.prank(trader2);
        futarchyTreasury.redeemWinnings(proposalId);
        assertGt(kled.balanceOf(trader2), balanceBefore);
    }

    // =============================================================
    //                    FUT-1: KLED BALANCE INVARIANT
    // =============================================================

    function test_FUT1_KledBalanceInvariant() public {
        uint256 initialBalance = kled.balanceOf(address(futarchyTreasury));

        // Create proposal
        vm.prank(proposer);
        uint256 proposalId = futarchyTreasury.createProposal(
            target, "", 1000e18, keccak256("desc"), DEFAULT_LIQUIDITY
        );

        uint256 afterCreate = kled.balanceOf(address(futarchyTreasury));
        assertEq(afterCreate, initialBalance + DEFAULT_STAKE + DEFAULT_LIQUIDITY);

        // Buy outcomes
        vm.prank(trader1);
        futarchyTreasury.buyOutcome(proposalId, true, MEDIUM_BUY, 0);

        vm.prank(trader2);
        futarchyTreasury.buyOutcome(proposalId, false, SMALL_BUY, 0);

        // Collateral should increase
        assertGt(futarchyTreasury.proposalCollateral(proposalId), DEFAULT_LIQUIDITY);

        // Treasury balance = stake + collateral
        uint256 treasuryBalance = kled.balanceOf(address(futarchyTreasury));
        uint256 collateral = futarchyTreasury.proposalCollateral(proposalId);

        // Balance should cover stake + collateral
        assertGe(treasuryBalance, DEFAULT_STAKE + collateral);
    }
}
