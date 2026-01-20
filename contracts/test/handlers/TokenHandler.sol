// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title TokenHandler
 * @notice Handler contract for invariant testing of KLEDToken (ERC20Votes)
 * @dev Wraps token functions with bounded inputs for stateful fuzzing
 *
 * ## Invariants to Test
 * - INV-TOK-1: Sum(balances) == totalSupply
 * - INV-TOK-2: Sum(votingPower) == totalDelegated (no votes from nothing)
 * - INV-TOK-3: User votingPower <= user balance + delegated to user
 * - INV-TOK-4: Checkpoints are monotonically increasing in block number
 *
 * ## Ghost Variables
 * - ghost_sumBalances: Running sum of all balances
 * - ghost_sumDelegated: Running sum of all delegated votes
 */
contract TokenHandler is CommonBase, StdCheats, StdUtils {
    // ============ Contracts (set after SOL deploys) ============

    // IKLEDToken public token;

    // ============ Ghost Variables ============

    uint256 public ghost_totalTransfers;
    uint256 public ghost_totalDelegations;

    mapping(address => uint256) public ghost_balance;
    mapping(address => address) public ghost_delegate;

    // ============ Actors ============

    address[] public actors;
    address internal currentActor;

    // ============ Call Counters ============

    mapping(bytes32 => uint256) public calls;

    // ============ Constructor ============

    constructor() {
        // TODO: Accept token address after SOL deploys
        // token = IKLEDToken(_token);

        // Setup actors
        actors.push(makeAddr("token_alice"));
        actors.push(makeAddr("token_bob"));
        actors.push(makeAddr("token_proposer"));
        actors.push(makeAddr("token_whale"));
        actors.push(makeAddr("token_attacker"));
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

    // ============ Handler Functions ============

    /**
     * @notice Handler for transfer() - transfers tokens between actors
     * @dev Bounded to valid amounts (sender balance)
     *
     * Ghost updates:
     * - ghost_balance[from] -= amount
     * - ghost_balance[to] += amount
     * - ghost_totalTransfers++
     */
    function handler_transfer(
        uint256 actorSeed,
        uint256 toSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("transfer") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Select recipient (different from sender)
        // 2. Bound amount to sender's balance
        // 3. Transfer
        // 4. Update ghost variables
        //
        // address to = actors[bound(toSeed, 0, actors.length - 1)];
        // if (to == currentActor) return;
        //
        // uint256 balance = token.balanceOf(currentActor);
        // if (balance == 0) return;
        //
        // uint256 amount = bound(amountSeed, 1, balance);
        //
        // token.transfer(to, amount);
        //
        // ghost_balance[currentActor] -= amount;
        // ghost_balance[to] += amount;
        // ghost_totalTransfers++;
    }

    /**
     * @notice Handler for delegate() - delegates voting power
     * @dev Can delegate to self or another actor
     *
     * Ghost updates:
     * - ghost_delegate[from] = to
     * - ghost_totalDelegations++
     */
    function handler_delegate(
        uint256 actorSeed,
        uint256 delegateeSeed
    ) external useActor(actorSeed) countCall("delegate") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Select delegatee
        // 2. Delegate
        // 3. Update ghost variables
        //
        // address delegatee = actors[bound(delegateeSeed, 0, actors.length - 1)];
        //
        // token.delegate(delegatee);
        //
        // ghost_delegate[currentActor] = delegatee;
        // ghost_totalDelegations++;
    }

    /**
     * @notice Handler for approve() - approves spender
     * @dev Used for governance staking approvals
     */
    function handler_approve(
        uint256 actorSeed,
        address spender,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("approve") {
        // TODO: Implement after SOL deploys contracts
        //
        // uint256 amount = bound(amountSeed, 0, type(uint256).max);
        // token.approve(spender, amount);
    }

    /**
     * @notice Handler for transferFrom() - transfers on behalf of another
     * @dev Requires approval
     */
    function handler_transferFrom(
        uint256 actorSeed,
        uint256 fromSeed,
        uint256 toSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("transferFrom") {
        // TODO: Implement after SOL deploys contracts
    }

    // ============ Adversarial Handlers ============

    /**
     * @notice Simulates flash loan pattern (same-block borrow/repay)
     * @dev Should NOT affect voting power due to snapshots
     */
    function handler_flashLoanSimulation(
        uint256 actorSeed,
        uint256 amountSeed
    ) external useActor(actorSeed) countCall("flashLoan") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Record current voting power
        // 2. Simulate receiving large amount (via mint or transfer from whale)
        // 3. Check voting power at current block (should be unchanged due to checkpoints)
        // 4. Return tokens
        //
        // This verifies snapshot mechanism prevents flash loan attacks
    }

    /**
     * @notice Simulates delegation manipulation (delegate -> act -> undelegate)
     * @dev Should NOT allow double-voting
     */
    function handler_delegateManipulation(
        uint256 actorSeed,
        uint256 delegateeSeed
    ) external useActor(actorSeed) countCall("delegateManipulation") {
        // TODO: Implement after SOL deploys contracts
    }

    // ============ View Functions for Invariants ============

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function callSummary() external view {
        console.log("--- Token Call Summary ---");
        console.log("transfer:", calls["transfer"]);
        console.log("delegate:", calls["delegate"]);
        console.log("approve:", calls["approve"]);
        console.log("transferFrom:", calls["transferFrom"]);
        console.log("flashLoan:", calls["flashLoan"]);
        console.log("delegateManipulation:", calls["delegateManipulation"]);
    }
}
