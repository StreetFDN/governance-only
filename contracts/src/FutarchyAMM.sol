// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FutarchyAMM
 * @author Street Governance
 * @notice LMSR (Logarithmic Market Scoring Rule) Automated Market Maker for Futarchy
 * @dev Provides price discovery for prediction markets without holding tokens directly
 *
 * LMSR Formula:
 * - Cost(q) = b * ln(e^(qYes/b) + e^(qNo/b))
 * - Price_Yes = e^(qYes/b) / (e^(qYes/b) + e^(qNo/b))
 * - Price_No = e^(qNo/b) / (e^(qYes/b) + e^(qNo/b))
 *
 * Where:
 * - b = liquidity parameter (higher = more liquidity, less price impact)
 * - qYes/qNo = outstanding quantity of YES/NO tokens
 *
 * Invariants:
 * - AMM-1: priceOfYes + priceOfNo == 1e18 (within rounding tolerance)
 * - AMM-2: Price is bounded: 0 < price < 1e18 for both outcomes
 * - AMM-4: Only FutarchyTreasury can call buy(), sell(), createMarket()
 * - AMM-8: No arbitrage: buy(X) then sell(X) returns <= KLED spent
 */
contract FutarchyAMM is Initializable, UUPSUpgradeable, ReentrancyGuard {
    // =============================================================
    //                           ERRORS
    // =============================================================

    error OnlyTreasury();
    error ZeroAddress();
    error TreasuryAlreadySet();
    error MarketAlreadyExists();
    error MarketNotFound();
    error MarketNotActive();
    error InvalidLiquidity();
    error Overflow();

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when a new market is created
    event MarketCreated(
        uint256 indexed marketId,
        uint256 proposalId,
        bool isPass,
        uint256 liquidity
    );

    /// @notice Emitted when tokens are bought
    event TokensBought(
        uint256 indexed marketId,
        bool isYes,
        uint256 cost,
        uint256 tokens
    );

    /// @notice Emitted when tokens are sold
    event TokensSold(
        uint256 indexed marketId,
        bool isYes,
        uint256 tokens,
        uint256 returned
    );

    /// @notice Emitted when market is closed
    event MarketClosed(
        uint256 indexed marketId,
        uint256 finalYesPrice,
        uint256 finalNoPrice
    );

    /// @notice Emitted when treasury is set
    event TreasurySet(address indexed treasury);

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice Precision for fixed-point math (18 decimals)
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum value for q to prevent overflow in exp calculations
    /// @dev With b = 10000e18, max q = 50 * b to keep exp(q/b) reasonable
    int256 public constant MAX_Q = 500_000e18;

    /// @notice Minimum value for q
    int256 public constant MIN_Q = -500_000e18;

    /// @notice Minimum TWAP window for price queries (SEC-028 fix)
    uint256 public constant MIN_TWAP_WINDOW = 1 hours;

    /// @notice Default TWAP window for resolution
    uint256 public constant DEFAULT_TWAP_WINDOW = 24 hours;

    // =============================================================
    //                           STRUCTS
    // =============================================================

    /// @notice Market state for a single outcome (PASS or FAIL)
    struct Market {
        uint256 proposalId;      // Associated proposal
        bool isPass;             // true = PASS market, false = FAIL market
        uint256 b;               // Liquidity parameter
        int256 qYes;             // Outstanding YES tokens (can be negative)
        int256 qNo;              // Outstanding NO tokens (can be negative)
        uint256 totalCollateral; // KLED backing the market
        bool active;             // Trading allowed
        uint256 createdAt;       // Market creation timestamp
    }

    /// @notice TWAP observation for price tracking (SEC-028 fix)
    struct TWAPObservation {
        uint256 timestamp;
        uint256 priceCumulativeYes;
        uint256 priceCumulativeNo;
    }

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Address of FutarchyTreasury (only caller)
    address public treasury;

    /// @notice Counter for market IDs
    uint256 public marketCount;

    /// @notice Market data by ID
    mapping(uint256 => Market) public markets;

    /// @notice TWAP cumulative prices (SEC-028 fix for flash loan resistance)
    /// @dev marketId => priceCumulativeYes (accumulated price * time)
    mapping(uint256 => uint256) public priceCumulativeYes;

    /// @notice TWAP cumulative NO prices
    /// @dev marketId => priceCumulativeNo
    mapping(uint256 => uint256) public priceCumulativeNo;

    /// @notice Last TWAP update timestamp
    /// @dev marketId => lastUpdateTimestamp
    mapping(uint256 => uint256) public twapLastUpdate;

    /// @notice Storage gap for future upgrades
    uint256[44] private __gap;

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

    /// @notice Initialize the AMM
    function initialize() external initializer {
        // Nothing to initialize - treasury set separately
    }

    // =============================================================
    //                      TREASURY MANAGEMENT
    // =============================================================

    /// @notice Set the treasury address (can only be set once)
    function setTreasury(address treasury_) external {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury != address(0)) revert TreasuryAlreadySet();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert OnlyTreasury();
        _;
    }

    // =============================================================
    //                      MARKET CREATION
    // =============================================================

    /**
     * @notice Create a new market for a proposal outcome
     * @param proposalId The proposal this market is for
     * @param isPass True for PASS market, false for FAIL market
     * @param liquidity Initial liquidity (determines 'b' parameter)
     * @return marketId The created market's ID
     */
    function createMarket(
        uint256 proposalId,
        bool isPass,
        uint256 liquidity
    ) external onlyTreasury nonReentrant returns (uint256 marketId) {
        if (liquidity == 0) revert InvalidLiquidity();

        marketId = marketCount++;

        // b = liquidity parameter, controls price sensitivity
        // Higher b = more liquidity, less price impact per trade
        uint256 b = liquidity;

        markets[marketId] = Market({
            proposalId: proposalId,
            isPass: isPass,
            b: b,
            qYes: 0,  // Start at 50/50
            qNo: 0,
            totalCollateral: liquidity,
            active: true,
            createdAt: block.timestamp
        });

        // Initialize TWAP (SEC-028 fix)
        twapLastUpdate[marketId] = block.timestamp;
        // Initial prices are 50/50 = 0.5e18 each
        // No cumulative yet since time elapsed = 0

        emit MarketCreated(marketId, proposalId, isPass, liquidity);
    }

    // =============================================================
    //                      TRADING FUNCTIONS
    // =============================================================

    /**
     * @notice Buy YES or NO tokens
     * @dev Called by Treasury when user wants to buy outcome tokens
     *      Includes TWAP update for flash loan resistance (SEC-028)
     * @param marketId The market to trade in
     * @param isYes True to buy YES tokens, false for NO
     * @param maxCost Maximum KLED to spend
     * @param deadline Transaction deadline timestamp (SEC-030 fix)
     * @return cost Actual KLED cost
     * @return tokensBought Amount of tokens purchased
     */
    function buy(
        uint256 marketId,
        bool isYes,
        uint256 maxCost,
        uint256 deadline
    ) external onlyTreasury nonReentrant returns (uint256 cost, uint256 tokensBought) {
        require(block.timestamp <= deadline, "Transaction expired");

        Market storage market = markets[marketId];
        if (!market.active) revert MarketNotActive();

        // Update TWAP BEFORE state change (SEC-028 fix)
        _updateTWAP(marketId);

        // For simplicity, we mint tokens equal to the cost
        // The price paid reflects the probability
        tokensBought = maxCost;
        cost = getCost(marketId, isYes, tokensBought);

        if (cost > maxCost) {
            // Adjust tokens to fit within maxCost
            tokensBought = _calcTokensForCost(market, isYes, maxCost);
            cost = maxCost;
        }

        // Update market state
        if (isYes) {
            market.qYes += int256(tokensBought);
            if (market.qYes > MAX_Q) revert Overflow();
        } else {
            market.qNo += int256(tokensBought);
            if (market.qNo > MAX_Q) revert Overflow();
        }
        market.totalCollateral += cost;

        emit TokensBought(marketId, isYes, cost, tokensBought);
    }

    /**
     * @notice Sell YES or NO tokens back to the market
     * @dev Includes TWAP update for flash loan resistance (SEC-028)
     * @param marketId The market to trade in
     * @param isYes True to sell YES tokens, false for NO
     * @param tokens Amount of tokens to sell
     * @param minReturn Minimum KLED to receive
     * @param deadline Transaction deadline timestamp (SEC-030 fix)
     * @return returned Amount of KLED returned
     */
    function sell(
        uint256 marketId,
        bool isYes,
        uint256 tokens,
        uint256 minReturn,
        uint256 deadline
    ) external onlyTreasury nonReentrant returns (uint256 returned) {
        require(block.timestamp <= deadline, "Transaction expired");

        Market storage market = markets[marketId];
        if (!market.active) revert MarketNotActive();

        // Update TWAP BEFORE state change (SEC-028 fix)
        _updateTWAP(marketId);

        returned = getReturn(marketId, isYes, tokens);
        require(returned >= minReturn, "Slippage exceeded");

        // Update market state
        if (isYes) {
            market.qYes -= int256(tokens);
            if (market.qYes < MIN_Q) revert Overflow();
        } else {
            market.qNo -= int256(tokens);
            if (market.qNo < MIN_Q) revert Overflow();
        }
        market.totalCollateral -= returned;

        emit TokensSold(marketId, isYes, tokens, returned);
    }

    /**
     * @notice Close a market and record final TWAP prices (SEC-028 fix)
     * @dev Uses TWAP for manipulation resistance, not spot price
     * @param marketId The market to close
     * @return finalYesPrice Final YES TWAP price (0-1e18)
     * @return finalNoPrice Final NO TWAP price (0-1e18)
     */
    function closeMarket(
        uint256 marketId
    ) external onlyTreasury nonReentrant returns (uint256 finalYesPrice, uint256 finalNoPrice) {
        Market storage market = markets[marketId];
        if (!market.active) revert MarketNotActive();

        // Final TWAP update
        _updateTWAP(marketId);

        market.active = false;

        // Use TWAP prices for resolution, NOT spot prices (SEC-028 critical fix)
        (finalYesPrice, finalNoPrice) = getTWAP(marketId, DEFAULT_TWAP_WINDOW);

        emit MarketClosed(marketId, finalYesPrice, finalNoPrice);
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get the current price of YES or NO tokens
     * @dev Price_Yes = e^(qYes/b) / (e^(qYes/b) + e^(qNo/b))
     * @param marketId The market to query
     * @param isYes True for YES price, false for NO price
     * @return price Price in 18 decimal precision (0 to 1e18)
     */
    function getPrice(uint256 marketId, bool isYes) public view returns (uint256) {
        Market storage market = markets[marketId];
        if (market.b == 0) revert MarketNotFound();

        // Use simplified calculation to avoid overflow
        // exp(qYes/b) / (exp(qYes/b) + exp(qNo/b))
        // = 1 / (1 + exp((qNo - qYes)/b))

        int256 diff;
        if (isYes) {
            diff = market.qNo - market.qYes;
        } else {
            diff = market.qYes - market.qNo;
        }

        // Calculate exp(diff/b)
        // For numerical stability, we use: price = 1/(1 + exp(diff/b))
        uint256 expValue = _exp(diff, market.b);

        // price = PRECISION / (1 + expValue/PRECISION)
        // = PRECISION * PRECISION / (PRECISION + expValue)
        return (PRECISION * PRECISION) / (PRECISION + expValue);
    }

    /**
     * @notice Calculate cost to buy a certain amount of tokens
     * @dev Cost = C(q + delta) - C(q) where C is the LMSR cost function
     * @param marketId The market
     * @param isYes True for YES tokens, false for NO
     * @param amount Number of tokens to buy
     * @return cost KLED cost
     */
    function getCost(
        uint256 marketId,
        bool isYes,
        uint256 amount
    ) public view returns (uint256) {
        Market storage market = markets[marketId];
        if (market.b == 0) revert MarketNotFound();

        // Cost = b * ln(sum(exp(q_i'/b))) - b * ln(sum(exp(q_i/b)))
        // For binary: Cost = b * [ln(exp(qYes'/b) + exp(qNo'/b)) - ln(exp(qYes/b) + exp(qNo/b))]

        int256 newQYes = market.qYes;
        int256 newQNo = market.qNo;

        if (isYes) {
            newQYes += int256(amount);
        } else {
            newQNo += int256(amount);
        }

        uint256 costBefore = _costFunction(market.qYes, market.qNo, market.b);
        uint256 costAfter = _costFunction(newQYes, newQNo, market.b);

        return costAfter > costBefore ? costAfter - costBefore : 0;
    }

    /**
     * @notice Calculate return for selling tokens
     * @param marketId The market
     * @param isYes True for YES tokens, false for NO
     * @param amount Number of tokens to sell
     * @return returned KLED returned
     */
    function getReturn(
        uint256 marketId,
        bool isYes,
        uint256 amount
    ) public view returns (uint256) {
        Market storage market = markets[marketId];
        if (market.b == 0) revert MarketNotFound();

        int256 newQYes = market.qYes;
        int256 newQNo = market.qNo;

        if (isYes) {
            newQYes -= int256(amount);
        } else {
            newQNo -= int256(amount);
        }

        uint256 costBefore = _costFunction(market.qYes, market.qNo, market.b);
        uint256 costAfter = _costFunction(newQYes, newQNo, market.b);

        return costBefore > costAfter ? costBefore - costAfter : 0;
    }

    /**
     * @notice Get market information
     */
    function getMarket(uint256 marketId) external view returns (
        uint256 proposalId,
        bool isPass,
        uint256 b,
        int256 qYes,
        int256 qNo,
        uint256 totalCollateral,
        bool active
    ) {
        Market storage m = markets[marketId];
        return (m.proposalId, m.isPass, m.b, m.qYes, m.qNo, m.totalCollateral, m.active);
    }

    // =============================================================
    //                    TWAP FUNCTIONS (SEC-028 FIX)
    // =============================================================

    /**
     * @notice Update TWAP accumulators
     * @dev Called before every trade to maintain accurate time-weighted prices
     *      This prevents flash loan manipulation by spreading price impact over time
     * @param marketId The market to update
     */
    function _updateTWAP(uint256 marketId) internal {
        uint256 lastUpdate = twapLastUpdate[marketId];
        uint256 timeElapsed = block.timestamp - lastUpdate;

        if (timeElapsed > 0) {
            // Cap time elapsed to prevent overflow (1 week max per update)
            // Prices are 1e18 max, so 1e18 * 604800 = 6e23 which is safe
            uint256 MAX_TIME_ELAPSED = 7 days;
            if (timeElapsed > MAX_TIME_ELAPSED) {
                timeElapsed = MAX_TIME_ELAPSED;
            }

            // Get current prices
            uint256 currentYesPrice = getPrice(marketId, true);
            uint256 currentNoPrice = getPrice(marketId, false);

            // Accumulate price * time
            // This creates a time-weighted average resistant to flash loans
            // Safe: max price is 1e18, max timeElapsed is 604800, product < 1e24
            priceCumulativeYes[marketId] += currentYesPrice * timeElapsed;
            priceCumulativeNo[marketId] += currentNoPrice * timeElapsed;

            twapLastUpdate[marketId] = block.timestamp;
        }
    }

    /**
     * @notice Get Time-Weighted Average Price over a window
     * @dev Critical for flash loan resistance - uses accumulated prices over time
     *      If window is longer than market existence, uses full market duration
     * @param marketId The market to query
     * @param windowSeconds Time window in seconds (e.g., 24 hours = 86400)
     * @return twapYes TWAP of YES price (0-1e18)
     * @return twapNo TWAP of NO price (0-1e18)
     */
    function getTWAP(
        uint256 marketId,
        uint256 windowSeconds
    ) public view returns (uint256 twapYes, uint256 twapNo) {
        Market storage market = markets[marketId];
        if (market.b == 0) revert MarketNotFound();

        uint256 currentTime = block.timestamp;
        uint256 marketAge = currentTime - market.createdAt;

        // Use minimum of requested window and market age
        uint256 effectiveWindow = windowSeconds > marketAge ? marketAge : windowSeconds;

        // If market is very new (< 1 minute), return current spot price
        // This is acceptable since manipulation window is too short
        if (effectiveWindow < 60) {
            return (getPrice(marketId, true), getPrice(marketId, false));
        }

        // Calculate current cumulative (including time since last update)
        uint256 timeElapsedSinceUpdate = currentTime - twapLastUpdate[marketId];

        // Cap time elapsed to prevent overflow (1 week max)
        uint256 MAX_TIME_ELAPSED = 7 days;
        if (timeElapsedSinceUpdate > MAX_TIME_ELAPSED) {
            timeElapsedSinceUpdate = MAX_TIME_ELAPSED;
        }

        uint256 currentYesPrice = getPrice(marketId, true);
        uint256 currentNoPrice = getPrice(marketId, false);

        uint256 currentCumulativeYes = priceCumulativeYes[marketId] + (currentYesPrice * timeElapsedSinceUpdate);
        uint256 currentCumulativeNo = priceCumulativeNo[marketId] + (currentNoPrice * timeElapsedSinceUpdate);

        // TWAP = cumulative / time
        // For simplicity, we use full market duration as the window
        // A more sophisticated implementation would store historical observations
        twapYes = currentCumulativeYes / marketAge;
        twapNo = currentCumulativeNo / marketAge;

        return (twapYes, twapNo);
    }

    /**
     * @notice Force update TWAP (can be called by anyone to poke the oracle)
     * @param marketId The market to update
     */
    function pokeTWAP(uint256 marketId) external {
        Market storage market = markets[marketId];
        if (market.b == 0) revert MarketNotFound();
        if (!market.active) revert MarketNotActive();

        _updateTWAP(marketId);
    }

    // =============================================================
    //                    INTERNAL MATH FUNCTIONS
    // =============================================================

    /**
     * @notice LMSR cost function: C(q) = b * ln(exp(qYes/b) + exp(qNo/b))
     * @dev Uses numerical approximation to avoid overflow
     */
    function _costFunction(
        int256 qYes,
        int256 qNo,
        uint256 b
    ) internal pure returns (uint256) {
        // For numerical stability, factor out max(qYes, qNo)
        // C = b * ln(exp(qYes/b) + exp(qNo/b))
        // = b * ln(exp(max/b) * (exp((qYes-max)/b) + exp((qNo-max)/b)))
        // = b * (max/b + ln(exp((qYes-max)/b) + exp((qNo-max)/b)))
        // = max + b * ln(exp((qYes-max)/b) + exp((qNo-max)/b))

        int256 maxQ = qYes > qNo ? qYes : qNo;

        uint256 expYesDiff = _exp(qYes - maxQ, b);
        uint256 expNoDiff = _exp(qNo - maxQ, b);

        uint256 sumExp = expYesDiff + expNoDiff;
        uint256 lnSum = _ln(sumExp);

        // Result = maxQ + b * lnSum / PRECISION
        int256 result = maxQ + int256((b * lnSum) / PRECISION);

        return result > 0 ? uint256(result) : 0;
    }

    /**
     * @notice Calculate exp(x/b) with 18 decimal precision
     * @dev Uses Taylor series approximation for |x/b| <= 20
     */
    function _exp(int256 x, uint256 b) internal pure returns (uint256) {
        if (b == 0) return PRECISION;

        // Calculate x * PRECISION / b to get fixed-point x/b
        int256 xOverB = (x * int256(PRECISION)) / int256(b);

        // Clamp to reasonable range to prevent overflow
        if (xOverB > 20 * int256(PRECISION)) {
            return type(uint256).max / 2; // Large but not overflow
        }
        if (xOverB < -20 * int256(PRECISION)) {
            return 0;
        }

        // For values close to 0, use Taylor series
        // exp(x) ≈ 1 + x + x²/2 + x³/6 + x⁴/24 + x⁵/120

        bool negative = xOverB < 0;
        uint256 absX = negative ? uint256(-xOverB) : uint256(xOverB);

        // Taylor series for exp(x)
        uint256 result = PRECISION; // 1
        uint256 term = absX;

        // Add x term
        result = negative ? result - term : result + term;

        // Add x²/2 term
        term = (term * absX) / PRECISION / 2;
        result += term;

        // Add x³/6 term
        term = (term * absX) / PRECISION / 3;
        result = negative ? result - term : result + term;

        // Add x⁴/24 term
        term = (term * absX) / PRECISION / 4;
        result += term;

        // Add x⁵/120 term
        term = (term * absX) / PRECISION / 5;
        result = negative ? result - term : result + term;

        // Add x⁶/720 term
        term = (term * absX) / PRECISION / 6;
        result += term;

        return result;
    }

    /**
     * @notice Calculate ln(x) with 18 decimal precision
     * @dev Uses approximation ln(x) = 2 * sum((y-1)/(y+1))^(2n+1)/(2n+1) where y = x
     */
    function _ln(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        if (x == PRECISION) return 0;

        // Normalize x to range [1, 2) by factoring out powers of 2
        uint256 result = 0;
        uint256 y = x;

        // ln(2) ≈ 0.693147... in 18 decimal
        uint256 LN2 = 693147180559945309;

        while (y >= 2 * PRECISION) {
            result += LN2;
            y = y / 2;
        }

        while (y < PRECISION) {
            result -= LN2;
            y = y * 2;
        }

        // Now 1 <= y < 2, use series expansion
        // ln(y) = 2 * ((y-1)/(y+1) + ((y-1)/(y+1))³/3 + ((y-1)/(y+1))⁵/5 + ...)

        uint256 yMinus1 = y - PRECISION;
        uint256 yPlus1 = y + PRECISION;
        uint256 z = (yMinus1 * PRECISION) / yPlus1;  // (y-1)/(y+1)
        uint256 zSquared = (z * z) / PRECISION;

        uint256 term = z;
        uint256 seriesSum = term;

        // Add z³/3
        term = (term * zSquared) / PRECISION;
        seriesSum += term / 3;

        // Add z⁵/5
        term = (term * zSquared) / PRECISION;
        seriesSum += term / 5;

        // Add z⁷/7
        term = (term * zSquared) / PRECISION;
        seriesSum += term / 7;

        result += 2 * seriesSum;

        return result;
    }

    /**
     * @notice Calculate tokens that can be bought for a given cost
     */
    function _calcTokensForCost(
        Market storage market,
        bool isYes,
        uint256 maxCost
    ) internal view returns (uint256) {
        // Binary search for tokens
        uint256 low = 0;
        uint256 high = maxCost * 2; // Upper bound estimate

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;

            int256 newQYes = market.qYes;
            int256 newQNo = market.qNo;

            if (isYes) {
                newQYes += int256(mid);
            } else {
                newQNo += int256(mid);
            }

            uint256 costBefore = _costFunction(market.qYes, market.qNo, market.b);
            uint256 costAfter = _costFunction(newQYes, newQNo, market.b);
            uint256 cost = costAfter > costBefore ? costAfter - costBefore : 0;

            if (cost <= maxCost) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    // =============================================================
    //                      UUPS UPGRADE
    // =============================================================

    function _authorizeUpgrade(address) internal override onlyTreasury {}
}
