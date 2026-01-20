// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FutarchyAMM} from "../src/FutarchyAMM.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title FutarchyAMM Tests
 * @notice Comprehensive tests for LMSR market maker with TWAP
 *
 * Invariants tested:
 * - AMM-1: priceOfYes + priceOfNo == 1e18 (within rounding tolerance)
 * - AMM-2: Price is bounded: 0 < price < 1e18 for both outcomes
 * - AMM-4: Only FutarchyTreasury can call buy(), sell(), createMarket()
 * - AMM-7: Cost monotonically increasing with quantity
 * - AMM-8: No arbitrage: buy(X) then sell(X) returns <= KLED spent
 * - AMM-9: Cannot trade after closeMarket
 * - AMM-10: Liquidity parameter immutable after creation
 * - AMM-11: Overflow protection for extreme values
 * - SEC-028: TWAP resistance to flash loan manipulation
 * - SEC-030: Deadline protection against stale transactions
 */
contract FutarchyAMMTest is Test {
    FutarchyAMM public amm;
    FutarchyAMM public ammImpl;

    address public treasury = address(0x1234);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_LIQUIDITY = 10_000e18;

    // Default deadline 1 hour in the future
    uint256 internal deadline;

    // Events
    event MarketCreated(uint256 indexed marketId, uint256 proposalId, bool isPass, uint256 liquidity);
    event TokensBought(uint256 indexed marketId, bool isYes, uint256 cost, uint256 tokens);
    event TokensSold(uint256 indexed marketId, bool isYes, uint256 tokens, uint256 returned);
    event MarketClosed(uint256 indexed marketId, uint256 finalYesPrice, uint256 finalNoPrice);
    event TreasurySet(address indexed treasury);

    function setUp() public {
        // Deploy implementation
        ammImpl = new FutarchyAMM();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(ammImpl), initData);
        amm = FutarchyAMM(address(proxy));

        // Set treasury
        amm.setTreasury(treasury);

        // Set default deadline
        deadline = block.timestamp + 1 hours;
    }

    // =============================================================
    //                    INITIALIZATION TESTS
    // =============================================================

    function test_Initialize() public view {
        assertEq(amm.treasury(), treasury);
        assertEq(amm.marketCount(), 0);
        assertEq(amm.PRECISION(), 1e18);
    }

    function test_SetTreasury_EmitsEvent() public {
        FutarchyAMM freshAmm = new FutarchyAMM();
        bytes memory initData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshAmm), initData);
        FutarchyAMM ammProxy = FutarchyAMM(address(proxy));

        vm.expectEmit(true, false, false, false);
        emit TreasurySet(treasury);
        ammProxy.setTreasury(treasury);
    }

    function test_SetTreasury_RevertZeroAddress() public {
        FutarchyAMM freshAmm = new FutarchyAMM();
        bytes memory initData = abi.encodeWithSelector(FutarchyAMM.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(freshAmm), initData);
        FutarchyAMM ammProxy = FutarchyAMM(address(proxy));

        vm.expectRevert(FutarchyAMM.ZeroAddress.selector);
        ammProxy.setTreasury(address(0));
    }

    function test_SetTreasury_RevertAlreadySet() public {
        vm.expectRevert(FutarchyAMM.TreasuryAlreadySet.selector);
        amm.setTreasury(alice);
    }

    // =============================================================
    //                    MARKET CREATION TESTS
    // =============================================================

    function test_CreateMarket_Success() public {
        vm.prank(treasury);
        vm.expectEmit(true, false, false, true);
        emit MarketCreated(0, 1, true, DEFAULT_LIQUIDITY);

        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        assertEq(marketId, 0);
        assertEq(amm.marketCount(), 1);

        (
            uint256 proposalId,
            bool isPass,
            uint256 b,
            int256 qYes,
            int256 qNo,
            uint256 totalCollateral,
            bool active
        ) = amm.getMarket(marketId);

        assertEq(proposalId, 1);
        assertTrue(isPass);
        assertEq(b, DEFAULT_LIQUIDITY);
        assertEq(qYes, 0);
        assertEq(qNo, 0);
        assertEq(totalCollateral, DEFAULT_LIQUIDITY);
        assertTrue(active);
    }

    function test_CreateMarket_MultipleMarkets() public {
        vm.startPrank(treasury);
        uint256 market0 = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        uint256 market1 = amm.createMarket(1, false, DEFAULT_LIQUIDITY);
        uint256 market2 = amm.createMarket(2, true, DEFAULT_LIQUIDITY * 2);
        vm.stopPrank();

        assertEq(market0, 0);
        assertEq(market1, 1);
        assertEq(market2, 2);
        assertEq(amm.marketCount(), 3);
    }

    function test_CreateMarket_RevertNotTreasury() public {
        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.createMarket(1, true, DEFAULT_LIQUIDITY);
    }

    function test_CreateMarket_RevertZeroLiquidity() public {
        vm.prank(treasury);
        vm.expectRevert(FutarchyAMM.InvalidLiquidity.selector);
        amm.createMarket(1, true, 0);
    }

    // =============================================================
    //                    AMM-1: PRICE SUM = 1
    // =============================================================

    function test_AMM1_PriceSumEqualsOne_Initial() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice, PRECISION / 2, 0.01e18);
        assertApproxEqRel(noPrice, PRECISION / 2, 0.01e18);
        assertApproxEqRel(yesPrice + noPrice, PRECISION, 0.01e18);
    }

    function test_AMM1_PriceSumEqualsOne_AfterBuyYes() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice + noPrice, PRECISION, 0.02e18);
        assertGt(yesPrice, noPrice);
        vm.stopPrank();
    }

    function test_AMM1_PriceSumEqualsOne_AfterBuyNo() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, false, 1000e18, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice + noPrice, PRECISION, 0.02e18);
        assertGt(noPrice, yesPrice);
        vm.stopPrank();
    }

    function testFuzz_AMM1_PriceSumEqualsOne(uint256 buyAmount) public {
        // Bound to amounts that won't overflow LMSR Taylor series math
        buyAmount = bound(buyAmount, 1e18, 10_000e18);

        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, buyAmount, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice + noPrice, PRECISION, 0.05e18);
        vm.stopPrank();
    }

    // =============================================================
    //                    AMM-2: PRICE BOUNDED
    // =============================================================

    function test_AMM2_PriceBounded_Initial() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertGt(yesPrice, 0);
        assertLt(yesPrice, PRECISION);
        assertGt(noPrice, 0);
        assertLt(noPrice, PRECISION);
    }

    function test_AMM2_PriceBounded_AfterLargeBuy() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        // Use an amount that won't overflow LMSR Taylor series math
        amm.buy(marketId, true, 8_000e18, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertGt(yesPrice, 0);
        assertLt(yesPrice, PRECISION);
        assertGt(noPrice, 0);
        assertLt(noPrice, PRECISION);
        vm.stopPrank();
    }

    function testFuzz_AMM2_PriceBounded(uint256 buyAmount, bool isYes) public {
        // Bound to amounts that won't overflow LMSR Taylor series math
        buyAmount = bound(buyAmount, 1e18, 10_000e18);

        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, isYes, buyAmount, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertGt(yesPrice, 0);
        assertLe(yesPrice, PRECISION);
        assertGt(noPrice, 0);
        assertLe(noPrice, PRECISION);
        vm.stopPrank();
    }

    // =============================================================
    //                    AMM-4: ACCESS CONTROL
    // =============================================================

    function test_AMM4_OnlyTreasury_CreateMarket() public {
        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.createMarket(1, true, DEFAULT_LIQUIDITY);
    }

    function test_AMM4_OnlyTreasury_Buy() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.buy(marketId, true, 100e18, deadline);
    }

    function test_AMM4_OnlyTreasury_Sell() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 100e18, deadline);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.sell(marketId, true, 50e18, 0, deadline);
    }

    function test_AMM4_OnlyTreasury_CloseMarket() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.closeMarket(marketId);
    }

    // =============================================================
    //                    AMM-7: COST MONOTONIC
    // =============================================================

    function test_AMM7_CostIncreases() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 cost1 = amm.getCost(marketId, true, 100e18);
        uint256 cost2 = amm.getCost(marketId, true, 200e18);
        uint256 cost3 = amm.getCost(marketId, true, 300e18);

        assertLt(cost1, cost2);
        assertLt(cost2, cost3);
    }

    function test_AMM7_CostIncreases_WithPriceImpact() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 costBefore = amm.getCost(marketId, true, 100e18);
        amm.buy(marketId, true, 1000e18, deadline);
        uint256 costAfter = amm.getCost(marketId, true, 100e18);

        assertGt(costAfter, costBefore);
        vm.stopPrank();
    }

    function testFuzz_AMM7_CostMonotonic(uint256 amount1, uint256 amount2) public {
        // Bound to amounts that won't overflow LMSR Taylor series math
        amount1 = bound(amount1, 1e18, 5_000e18);
        amount2 = bound(amount2, amount1 + 1e18, 10_000e18);

        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 cost1 = amm.getCost(marketId, true, amount1);
        uint256 cost2 = amm.getCost(marketId, true, amount2);

        assertLe(cost1, cost2);
    }

    // =============================================================
    //                    AMM-8: NO ARBITRAGE
    // =============================================================

    function test_AMM8_NoArbitrage_BuySell() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        (uint256 spent, uint256 tokens) = amm.buy(marketId, true, 1000e18, deadline);
        uint256 returned = amm.sell(marketId, true, tokens, 0, deadline);

        assertLe(returned, spent);
        vm.stopPrank();
    }

    function testFuzz_AMM8_NoArbitrage(uint256 buyAmount) public {
        // Bound to amounts that won't overflow LMSR Taylor series math
        buyAmount = bound(buyAmount, 100e18, 8_000e18);

        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        (uint256 spent, uint256 tokens) = amm.buy(marketId, true, buyAmount, deadline);
        uint256 returned = amm.sell(marketId, true, tokens, 0, deadline);

        assertLe(returned, spent);
        vm.stopPrank();
    }

    // =============================================================
    //                    AMM-9: NO TRADING AFTER CLOSE
    // =============================================================

    function test_AMM9_CannotBuyAfterClose() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(block.timestamp + 2 hours);
        amm.closeMarket(marketId);

        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.buy(marketId, true, 100e18, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function test_AMM9_CannotSellAfterClose() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        vm.warp(block.timestamp + 2 hours);
        amm.closeMarket(marketId);

        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.sell(marketId, true, 500e18, 0, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function test_AMM9_CannotCloseAlreadyClosed() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(block.timestamp + 2 hours);
        amm.closeMarket(marketId);

        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.closeMarket(marketId);
        vm.stopPrank();
    }

    // =============================================================
    //                    AMM-10: LIQUIDITY IMMUTABLE
    // =============================================================

    function test_AMM10_LiquidityImmutable() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        (, , uint256 bBefore, , , , ) = amm.getMarket(marketId);

        amm.buy(marketId, true, 5000e18, deadline);
        amm.buy(marketId, false, 3000e18, deadline);
        amm.sell(marketId, true, 1000e18, 0, deadline);

        (, , uint256 bAfter, , , , ) = amm.getMarket(marketId);

        assertEq(bBefore, bAfter);
        vm.stopPrank();
    }

    // =============================================================
    //                    AMM-11: OVERFLOW PROTECTION
    // =============================================================

    function test_AMM11_OverflowProtection_MaxQ() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        int256 maxQ = amm.MAX_Q();

        vm.expectRevert(FutarchyAMM.Overflow.selector);
        amm.buy(marketId, true, uint256(maxQ) + 1e18, deadline);
        vm.stopPrank();
    }

    function test_AMM11_OverflowProtection_MinQ() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        // Buy a significant amount first to have some qYes
        amm.buy(marketId, true, 10_000e18, deadline);

        // Get current qYes to calculate how much we can sell before hitting MIN_Q
        (, , , int256 qYes, , , ) = amm.getMarket(marketId);

        // MIN_Q is -500_000e18, so selling qYes + |MIN_Q| + 1 should trigger overflow
        int256 minQ = amm.MIN_Q(); // -500_000e18
        uint256 extremeSell = uint256(qYes) + uint256(-minQ) + 1e18;

        vm.expectRevert(FutarchyAMM.Overflow.selector);
        amm.sell(marketId, true, extremeSell, 0, deadline);
        vm.stopPrank();
    }

    // =============================================================
    //                    SEC-030: DEADLINE TESTS
    // =============================================================

    function test_SEC030_BuyRevertExpiredDeadline() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(deadline + 1);

        vm.expectRevert("Transaction expired");
        amm.buy(marketId, true, 100e18, deadline);
        vm.stopPrank();
    }

    function test_SEC030_SellRevertExpiredDeadline() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        vm.warp(deadline + 1);

        vm.expectRevert("Transaction expired");
        amm.sell(marketId, true, 500e18, 0, deadline);
        vm.stopPrank();
    }

    function test_SEC030_DeadlineAtExactTime() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(deadline);
        amm.buy(marketId, true, 100e18, deadline);
        vm.stopPrank();
    }

    // =============================================================
    //                    SEC-028: TWAP TESTS
    // =============================================================

    function test_SEC028_TWAPInitialized() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        assertEq(amm.twapLastUpdate(marketId), block.timestamp);
        assertEq(amm.priceCumulativeYes(marketId), 0);
        assertEq(amm.priceCumulativeNo(marketId), 0);
    }

    function test_SEC028_TWAPUpdatesOnBuy() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 initialUpdate = amm.twapLastUpdate(marketId);

        vm.warp(block.timestamp + 1 hours);
        amm.buy(marketId, true, 1000e18, block.timestamp + 1 hours);

        assertGt(amm.twapLastUpdate(marketId), initialUpdate);
        assertGt(amm.priceCumulativeYes(marketId), 0);
        assertGt(amm.priceCumulativeNo(marketId), 0);
        vm.stopPrank();
    }

    function test_SEC028_TWAPUpdatesOnSell() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        vm.warp(block.timestamp + 1 hours);

        uint256 cumulativeBefore = amm.priceCumulativeYes(marketId);
        amm.sell(marketId, true, 500e18, 0, block.timestamp + 1 hours);

        assertGt(amm.priceCumulativeYes(marketId), cumulativeBefore);
        vm.stopPrank();
    }

    function test_SEC028_GetTWAPPrice() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        amm.buy(marketId, true, 2000e18, deadline);

        vm.warp(block.timestamp + 2 hours);
        amm.buy(marketId, false, 1000e18, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);

        (uint256 twapYes, uint256 twapNo) = amm.getTWAP(marketId, 1 hours);

        assertGt(twapYes, 0);
        assertGt(twapNo, 0);
        assertApproxEqRel(twapYes + twapNo, PRECISION, 0.1e18);
        vm.stopPrank();
    }

    function test_SEC028_PokeTWAP() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        amm.pokeTWAP(marketId);

        assertEq(amm.twapLastUpdate(marketId), block.timestamp);
    }

    function test_SEC028_PokeTWAPRevertClosedMarket() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.warp(block.timestamp + 2 hours);
        amm.closeMarket(marketId);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.pokeTWAP(marketId);
    }

    // =============================================================
    //                    BUY FUNCTION TESTS
    // =============================================================

    function test_Buy_EmitsEvent() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        vm.expectEmit(true, false, false, false);
        emit TokensBought(marketId, true, 0, 0);

        amm.buy(marketId, true, 1000e18, deadline);
        vm.stopPrank();
    }

    function test_Buy_UpdatesState() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        (, , , int256 qYesBefore, int256 qNoBefore, uint256 collateralBefore, ) = amm.getMarket(marketId);

        (uint256 cost, uint256 tokens) = amm.buy(marketId, true, 1000e18, deadline);

        (, , , int256 qYesAfter, int256 qNoAfter, uint256 collateralAfter, ) = amm.getMarket(marketId);

        assertEq(qYesAfter, qYesBefore + int256(tokens));
        assertEq(qNoAfter, qNoBefore);
        assertEq(collateralAfter, collateralBefore + cost);
        vm.stopPrank();
    }

    function test_Buy_MaxCostRespected() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 maxCost = 500e18;
        (uint256 cost, ) = amm.buy(marketId, true, maxCost, deadline);

        assertLe(cost, maxCost);
        vm.stopPrank();
    }

    function test_Buy_RevertMarketNotActive() public {
        // For non-existent markets, active is false so MarketNotActive is thrown
        // before the MarketNotFound check in getCost
        vm.prank(treasury);
        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.buy(999, true, 100e18, deadline);
    }

    // =============================================================
    //                    SELL FUNCTION TESTS
    // =============================================================

    function test_Sell_EmitsEvent() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        vm.expectEmit(true, false, false, false);
        emit TokensSold(marketId, true, 0, 0);

        amm.sell(marketId, true, 500e18, 0, deadline);
        vm.stopPrank();
    }

    function test_Sell_UpdatesState() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        (, uint256 tokensBought) = amm.buy(marketId, true, 1000e18, deadline);

        (, , , int256 qYesBefore, int256 qNoBefore, uint256 collateralBefore, ) = amm.getMarket(marketId);

        uint256 tokensToSell = tokensBought / 2;
        uint256 returned = amm.sell(marketId, true, tokensToSell, 0, deadline);

        (, , , int256 qYesAfter, int256 qNoAfter, uint256 collateralAfter, ) = amm.getMarket(marketId);

        assertEq(qYesAfter, qYesBefore - int256(tokensToSell));
        assertEq(qNoAfter, qNoBefore);
        assertEq(collateralAfter, collateralBefore - returned);
        vm.stopPrank();
    }

    function test_Sell_RevertSlippage() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        amm.buy(marketId, true, 1000e18, deadline);

        vm.expectRevert("Slippage exceeded");
        amm.sell(marketId, true, 100e18, type(uint256).max, deadline);
        vm.stopPrank();
    }

    function test_Sell_RevertMarketNotActive() public {
        // For non-existent markets, active is false so MarketNotActive is thrown
        // before the MarketNotFound check in getReturn
        vm.prank(treasury);
        vm.expectRevert(FutarchyAMM.MarketNotActive.selector);
        amm.sell(999, true, 100e18, 0, deadline);
    }

    // =============================================================
    //                    VIEW FUNCTION TESTS
    // =============================================================

    function test_GetPrice_RevertMarketNotFound() public {
        vm.expectRevert(FutarchyAMM.MarketNotFound.selector);
        amm.getPrice(999, true);
    }

    function test_GetCost_RevertMarketNotFound() public {
        vm.expectRevert(FutarchyAMM.MarketNotFound.selector);
        amm.getCost(999, true, 100e18);
    }

    function test_GetReturn_RevertMarketNotFound() public {
        vm.expectRevert(FutarchyAMM.MarketNotFound.selector);
        amm.getReturn(999, true, 100e18);
    }

    function test_GetMarket_Returns() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(42, true, DEFAULT_LIQUIDITY);

        (
            uint256 proposalId,
            bool isPass,
            uint256 b,
            int256 qYes,
            int256 qNo,
            uint256 totalCollateral,
            bool active
        ) = amm.getMarket(marketId);

        assertEq(proposalId, 42);
        assertTrue(isPass);
        assertEq(b, DEFAULT_LIQUIDITY);
        assertEq(qYes, 0);
        assertEq(qNo, 0);
        assertEq(totalCollateral, DEFAULT_LIQUIDITY);
        assertTrue(active);
    }

    // =============================================================
    //                    LMSR MATH TESTS
    // =============================================================

    function test_LMSR_InitialPrices5050() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice, PRECISION / 2, 0.01e18);
        assertApproxEqRel(noPrice, PRECISION / 2, 0.01e18);
    }

    function test_LMSR_PriceMovesWithBuys() public {
        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 yesPriceBefore = amm.getPrice(marketId, true);
        amm.buy(marketId, true, 5000e18, deadline);
        uint256 yesPriceAfter = amm.getPrice(marketId, true);

        assertGt(yesPriceAfter, yesPriceBefore);
        vm.stopPrank();
    }

    function test_LMSR_SymmetricPrices() public {
        vm.startPrank(treasury);

        uint256 market1 = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        uint256 market2 = amm.createMarket(2, true, DEFAULT_LIQUIDITY);

        amm.buy(market1, true, 5000e18, deadline);
        amm.buy(market2, false, 5000e18, deadline);

        uint256 yesPrice1 = amm.getPrice(market1, true);
        uint256 noPrice2 = amm.getPrice(market2, false);

        assertApproxEqRel(yesPrice1, noPrice2, 0.01e18);
        vm.stopPrank();
    }

    function test_LMSR_CostIncreasesSuperlinearly() public {
        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);

        uint256 cost1 = amm.getCost(marketId, true, 1000e18);
        uint256 cost2 = amm.getCost(marketId, true, 2000e18);

        assertGt(cost2, cost1 * 2);
    }

    // =============================================================
    //                    DIFFERENT LIQUIDITY TESTS
    // =============================================================

    function test_HighLiquidity_LessPriceImpact() public {
        vm.startPrank(treasury);

        uint256 lowLiqMarket = amm.createMarket(1, true, 1000e18);
        uint256 highLiqMarket = amm.createMarket(2, true, 100_000e18);

        uint256 lowLiqPriceBefore = amm.getPrice(lowLiqMarket, true);
        uint256 highLiqPriceBefore = amm.getPrice(highLiqMarket, true);

        amm.buy(lowLiqMarket, true, 500e18, deadline);
        amm.buy(highLiqMarket, true, 500e18, deadline);

        uint256 lowLiqPriceAfter = amm.getPrice(lowLiqMarket, true);
        uint256 highLiqPriceAfter = amm.getPrice(highLiqMarket, true);

        uint256 lowLiqPriceChange = lowLiqPriceAfter - lowLiqPriceBefore;
        uint256 highLiqPriceChange = highLiqPriceAfter - highLiqPriceBefore;

        assertGt(lowLiqPriceChange, highLiqPriceChange);
        vm.stopPrank();
    }

    function testFuzz_DifferentLiquidity(uint256 liquidity, uint256 buyAmount) public {
        liquidity = bound(liquidity, 100e18, 1_000_000e18);
        buyAmount = bound(buyAmount, 1e18, liquidity / 10);

        vm.startPrank(treasury);
        uint256 marketId = amm.createMarket(1, true, liquidity);

        amm.buy(marketId, true, buyAmount, deadline);

        uint256 yesPrice = amm.getPrice(marketId, true);
        uint256 noPrice = amm.getPrice(marketId, false);

        assertApproxEqRel(yesPrice + noPrice, PRECISION, 0.05e18);
        assertGt(yesPrice, 0);
        assertLt(yesPrice, PRECISION);
        assertGt(noPrice, 0);
        assertLt(noPrice, PRECISION);
        vm.stopPrank();
    }

    // =============================================================
    //                    UPGRADE TESTS
    // =============================================================

    function test_Upgrade_OnlyTreasury() public {
        FutarchyAMM newImpl = new FutarchyAMM();

        vm.prank(alice);
        vm.expectRevert(FutarchyAMM.OnlyTreasury.selector);
        amm.upgradeToAndCall(address(newImpl), "");
    }

    function test_Upgrade_TreasuryCanUpgrade() public {
        FutarchyAMM newImpl = new FutarchyAMM();

        vm.prank(treasury);
        amm.upgradeToAndCall(address(newImpl), "");

        vm.prank(treasury);
        uint256 marketId = amm.createMarket(1, true, DEFAULT_LIQUIDITY);
        assertEq(marketId, 0);
    }
}
