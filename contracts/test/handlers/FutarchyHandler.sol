// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title FutarchyHandler
 * @notice Handler contract for invariant testing of FutarchyTreasury
 * @dev Wraps futarchy functions with bounded inputs for stateful fuzzing
 *
 * ## Key Invariants to Test
 * - INV-FUT-1: YES_supply + NO_supply = 2 * total_collateral
 * - INV-FUT-2: AMM reserves > 0 always
 * - INV-FUT-3: 0 < price < 1 (bounded)
 * - INV-FUT-4: Only one outcome can win
 * - INV-FUT-5: Collateral always redeemable post-resolution
 * - INV-FUT-6: Fees monotonically increase
 * - INV-FUT-7: No value leak (collateral in = collateral out)
 *
 * ## Ghost Variables
 * - ghost_totalDeposited: Total collateral ever deposited
 * - ghost_totalWithdrawn: Total collateral ever withdrawn
 * - ghost_totalFees: Total fees collected
 * - ghost_yesTradeVolume: Volume of YES token trades
 * - ghost_noTradeVolume: Volume of NO token trades
 */
contract FutarchyHandler is CommonBase, StdCheats, StdUtils {
    // ============ Contracts (set after SOL deploys) ============

    // IFutarchyTreasury public futarchy;
    // IERC20 public collateralToken;
    // IERC20 public yesToken;
    // IERC20 public noToken;

    // ============ Ghost Variables ============

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalRedeemed;
    uint256 public ghost_totalFeesPaid;
    uint256 public ghost_yesTradeVolume;
    uint256 public ghost_noTradeVolume;

    bool public ghost_isResolved;
    bool public ghost_yesWon;

    mapping(address => uint256) public ghost_userDeposits;
    mapping(address => uint256) public ghost_userYesBalance;
    mapping(address => uint256) public ghost_userNoBalance;

    // ============ Actors ============

    address[] public actors;
    address internal currentActor;

    // ============ Call Counters ============

    mapping(bytes32 => uint256) public calls;

    // ============ Constants ============

    uint256 public constant MIN_TRADE = 1 ether;
    uint256 public constant MAX_TRADE = 100_000 ether;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Constructor ============

    constructor() {
        // TODO: Accept contract addresses after SOL deploys
        // futarchy = IFutarchyTreasury(_futarchy);
        // collateralToken = futarchy.collateralToken();
        // yesToken = futarchy.yesToken();
        // noToken = futarchy.noToken();

        // Setup actors
        actors.push(makeAddr("futarchy_alice"));
        actors.push(makeAddr("futarchy_bob"));
        actors.push(makeAddr("futarchy_charlie"));
        actors.push(makeAddr("futarchy_whale"));
        actors.push(makeAddr("futarchy_trader"));
    }

    // ============ Modifiers ============

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier marketNotResolved() {
        if (ghost_isResolved) return;
        _;
    }

    modifier marketResolved() {
        if (!ghost_isResolved) return;
        _;
    }

    // ============ Handler Functions ============

    /**
     * @notice Handler for depositCollateral() - deposits collateral and mints YES/NO
     * @dev Bounded to available balance
     *
     * Ghost updates:
     * - ghost_totalDeposited += amount
     * - ghost_userDeposits[user] += amount
     * - ghost_userYesBalance[user] += amount
     * - ghost_userNoBalance[user] += amount
     */
    function handler_deposit(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("deposit") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 balance = collateralToken.balanceOf(currentActor);
        // if (balance == 0) return;
        //
        // uint256 amount = bound(amountSeed, MIN_TRADE, balance);
        //
        // collateralToken.approve(address(futarchy), amount);
        // futarchy.depositCollateral(amount);
        //
        // ghost_totalDeposited += amount;
        // ghost_userDeposits[currentActor] += amount;
        // ghost_userYesBalance[currentActor] += amount;
        // ghost_userNoBalance[currentActor] += amount;
    }

    /**
     * @notice Handler for redeemPair() - burns YES+NO to get collateral
     * @dev Bounded to minimum of YES and NO balance
     *
     * Ghost updates:
     * - ghost_totalWithdrawn += amount
     * - ghost_userYesBalance[user] -= amount
     * - ghost_userNoBalance[user] -= amount
     */
    function handler_redeemPair(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("redeemPair") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 yesBalance = yesToken.balanceOf(currentActor);
        // uint256 noBalance = noToken.balanceOf(currentActor);
        // uint256 maxRedeem = yesBalance < noBalance ? yesBalance : noBalance;
        //
        // if (maxRedeem == 0) return;
        //
        // uint256 amount = bound(amountSeed, 1, maxRedeem);
        //
        // futarchy.redeemPair(amount);
        //
        // ghost_totalWithdrawn += amount;
        // ghost_userYesBalance[currentActor] -= amount;
        // ghost_userNoBalance[currentActor] -= amount;
    }

    /**
     * @notice Handler for buyYes() - buys YES tokens from AMM
     * @dev Bounded to available collateral
     *
     * Ghost updates:
     * - ghost_yesTradeVolume += amountIn
     * - ghost_totalFeesPaid += fee
     */
    function handler_buyYes(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("buyYes") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 balance = collateralToken.balanceOf(currentActor);
        // if (balance < MIN_TRADE) return;
        //
        // uint256 amount = bound(amountSeed, MIN_TRADE, balance > MAX_TRADE ? MAX_TRADE : balance);
        //
        // collateralToken.approve(address(futarchy), amount);
        //
        // try futarchy.buyYes(amount, 0) returns (uint256 amountOut) {
        //     ghost_yesTradeVolume += amount;
        //     ghost_userYesBalance[currentActor] += amountOut;
        //     // Fee = amount * feeBps / BPS_DENOMINATOR
        // } catch {
        //     // Trade failed (e.g., slippage, insufficient liquidity)
        // }
    }

    /**
     * @notice Handler for buyNo() - buys NO tokens from AMM
     * @dev Bounded to available collateral
     *
     * Ghost updates:
     * - ghost_noTradeVolume += amountIn
     * - ghost_totalFeesPaid += fee
     */
    function handler_buyNo(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("buyNo") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 balance = collateralToken.balanceOf(currentActor);
        // if (balance < MIN_TRADE) return;
        //
        // uint256 amount = bound(amountSeed, MIN_TRADE, balance > MAX_TRADE ? MAX_TRADE : balance);
        //
        // collateralToken.approve(address(futarchy), amount);
        //
        // try futarchy.buyNo(amount, 0) returns (uint256 amountOut) {
        //     ghost_noTradeVolume += amount;
        //     ghost_userNoBalance[currentActor] += amountOut;
        // } catch {}
    }

    /**
     * @notice Handler for sellYes() - sells YES tokens to AMM
     * @dev Bounded to YES token balance
     */
    function handler_sellYes(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("sellYes") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 yesBalance = yesToken.balanceOf(currentActor);
        // if (yesBalance == 0) return;
        //
        // uint256 amount = bound(amountSeed, 1, yesBalance);
        //
        // yesToken.approve(address(futarchy), amount);
        //
        // try futarchy.sellYes(amount, 0) returns (uint256 amountOut) {
        //     ghost_yesTradeVolume += amount;
        //     ghost_userYesBalance[currentActor] -= amount;
        // } catch {}
    }

    /**
     * @notice Handler for sellNo() - sells NO tokens to AMM
     * @dev Bounded to NO token balance
     */
    function handler_sellNo(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("sellNo") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 noBalance = noToken.balanceOf(currentActor);
        // if (noBalance == 0) return;
        //
        // uint256 amount = bound(amountSeed, 1, noBalance);
        //
        // noToken.approve(address(futarchy), amount);
        //
        // try futarchy.sellNo(amount, 0) returns (uint256 amountOut) {
        //     ghost_noTradeVolume += amount;
        //     ghost_userNoBalance[currentActor] -= amount;
        // } catch {}
    }

    /**
     * @notice Handler for redeemWinnings() - redeems winning tokens post-resolution
     * @dev Only callable after market resolution
     */
    function handler_redeemWinnings(
        uint256 actorSeed
    ) external useActor(actorSeed) countCall("redeemWinnings") marketResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // try futarchy.redeemWinnings() returns (uint256 amountOut) {
        //     ghost_totalRedeemed += amountOut;
        //
        //     if (ghost_yesWon) {
        //         ghost_userYesBalance[currentActor] = 0;
        //     } else {
        //         ghost_userNoBalance[currentActor] = 0;
        //     }
        // } catch {}
    }

    /**
     * @notice Handler for time advancement
     * @dev Simulates time passing for market expiry
     */
    function handler_warp(uint256 secondsSeed) external countCall("warp") {
        uint256 seconds_ = bound(secondsSeed, 1 hours, 30 days);
        vm.warp(block.timestamp + seconds_);
    }

    /**
     * @notice Handler for market resolution (admin only)
     * @dev Only callable once, randomly determines winner
     */
    function handler_resolve(uint256 outcomeSeed) external countCall("resolve") marketNotResolved {
        // TODO: Implement after SOL deploys contracts
        //
        // This would normally be called by governance after proposal outcome
        // For testing, we randomly resolve
        //
        // bool yesWins = outcomeSeed % 2 == 0;
        //
        // vm.prank(owner);
        // futarchy.resolveMarket(yesWins);
        //
        // ghost_isResolved = true;
        // ghost_yesWon = yesWins;
    }

    // ============ View Functions for Invariants ============

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function callSummary() external view {
        console.log("--- Futarchy Call Summary ---");
        console.log("deposit:", calls["deposit"]);
        console.log("redeemPair:", calls["redeemPair"]);
        console.log("buyYes:", calls["buyYes"]);
        console.log("buyNo:", calls["buyNo"]);
        console.log("sellYes:", calls["sellYes"]);
        console.log("sellNo:", calls["sellNo"]);
        console.log("redeemWinnings:", calls["redeemWinnings"]);
        console.log("resolve:", calls["resolve"]);
        console.log("warp:", calls["warp"]);
        console.log("");
        console.log("--- Ghost Variables ---");
        console.log("totalDeposited:", ghost_totalDeposited);
        console.log("totalWithdrawn:", ghost_totalWithdrawn);
        console.log("totalRedeemed:", ghost_totalRedeemed);
        console.log("yesTradeVolume:", ghost_yesTradeVolume);
        console.log("noTradeVolume:", ghost_noTradeVolume);
        console.log("isResolved:", ghost_isResolved);
        console.log("yesWon:", ghost_yesWon);
    }
}
