// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title GovernorHandler
 * @notice Handler contract for invariant testing of StreetGovernor
 * @dev Wraps governance functions with bounded inputs for stateful fuzzing
 *
 * ## Tracked State (Ghost Variables)
 * - totalProposalsCreated: Count of all proposals
 * - totalStakedEver: Sum of all stakes deposited
 * - totalSlashed: Sum of all slashed amounts
 * - totalReturned: Sum of all returned stakes
 * - activeProposals: Set of proposals not yet finalized
 *
 * ## Invariants to Test
 * - INV-GOV-1: totalVotes <= snapshotSupply for any proposal
 * - INV-GOV-2: No double voting (hasVoted enforced)
 * - INV-GOV-3: Valid state transitions only
 * - INV-GOV-4: Contract balance >= sum(pending stakes)
 *
 * ## Invariants for Staking
 * - INV-STAKE-1: pendingStakes + slashed + returned == totalStakedEver
 * - INV-STAKE-2: slashed == 0.1 * failedProposalStakes
 * - INV-STAKE-3: No stake claimed twice
 */
contract GovernorHandler is CommonBase, StdCheats, StdUtils {
    // ============ Contracts (set after SOL deploys) ============

    // IStreetGovernor public governor;
    // IKLEDToken public token;

    // ============ Ghost Variables ============

    uint256 public ghost_totalProposalsCreated;
    uint256 public ghost_totalStakedEver;
    uint256 public ghost_totalSlashed;
    uint256 public ghost_totalReturned;
    uint256 public ghost_totalVotesCast;

    mapping(uint256 => bool) public ghost_proposalFinalized;
    mapping(uint256 => uint256) public ghost_proposalStake;
    mapping(uint256 => mapping(address => bool)) public ghost_hasVoted;

    // ============ Actors ============

    address[] public actors;
    address internal currentActor;

    // ============ Call Counters ============

    mapping(bytes32 => uint256) public calls;

    // ============ Constructor ============

    constructor() {
        // TODO: Accept governor and token addresses after SOL deploys
        // governor = IStreetGovernor(_governor);
        // token = IKLEDToken(_token);

        // Setup actors
        actors.push(makeAddr("handler_alice"));
        actors.push(makeAddr("handler_bob"));
        actors.push(makeAddr("handler_proposer"));
        actors.push(makeAddr("handler_whale"));
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
     * @notice Handler for propose() - creates a proposal with stake
     * @dev Bounded to actors with sufficient balance
     *
     * Ghost updates:
     * - ghost_totalProposalsCreated++
     * - ghost_totalStakedEver += PROPOSAL_STAKE
     * - ghost_proposalStake[proposalId] = PROPOSAL_STAKE
     */
    function handler_propose(
        uint256 actorSeed,
        string calldata title,
        string calldata description
    ) external useActor(actorSeed) countCall("propose") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Check if currentActor has >= 50K KLED
        // 2. Check if currentActor has approved governor
        // 3. Call governor.propose(title, description)
        // 4. Update ghost variables
        //
        // if (token.balanceOf(currentActor) < PROPOSAL_STAKE) return;
        // if (token.allowance(currentActor, address(governor)) < PROPOSAL_STAKE) {
        //     token.approve(address(governor), type(uint256).max);
        // }
        //
        // uint256 proposalId = governor.propose(title, description);
        //
        // ghost_totalProposalsCreated++;
        // ghost_totalStakedEver += PROPOSAL_STAKE;
        // ghost_proposalStake[proposalId] = PROPOSAL_STAKE;
    }

    /**
     * @notice Handler for vote() - casts a vote on a proposal
     * @dev Bounded to valid proposals and support values
     *
     * Ghost updates:
     * - ghost_totalVotesCast += weight
     * - ghost_hasVoted[proposalId][voter] = true
     */
    function handler_vote(
        uint256 actorSeed,
        uint256 proposalIdSeed,
        uint8 supportSeed
    ) external useActor(actorSeed) countCall("vote") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound proposalId to [1, proposalCount]
        // 2. Bound support to [0, 2] (Against, For, Abstain)
        // 3. Check proposal is in Active state
        // 4. Check voter hasn't voted
        // 5. Cast vote
        // 6. Update ghost variables
        //
        // uint256 proposalId = bound(proposalIdSeed, 1, governor.proposalCount());
        // uint8 support = uint8(bound(supportSeed, 0, 2));
        //
        // if (governor.state(proposalId) != ProposalState.Active) return;
        // if (governor.hasVoted(proposalId, currentActor)) return;
        //
        // uint256 weight = token.getPastVotes(currentActor, governor.proposalSnapshot(proposalId));
        // if (weight == 0) return;
        //
        // governor.vote(proposalId, support);
        //
        // ghost_totalVotesCast += weight;
        // ghost_hasVoted[proposalId][currentActor] = true;
    }

    /**
     * @notice Handler for execute() - executes a passed proposal
     * @dev Only succeeds if proposal passed and timelock elapsed
     *
     * Ghost updates:
     * - ghost_totalReturned += stake
     * - ghost_proposalFinalized[proposalId] = true
     */
    function handler_execute(uint256 proposalIdSeed) external countCall("execute") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound proposalId
        // 2. Check proposal can be executed
        // 3. Execute
        // 4. Update ghost variables (stake returned)
        //
        // uint256 proposalId = bound(proposalIdSeed, 1, governor.proposalCount());
        //
        // if (governor.state(proposalId) != ProposalState.Queued) return;
        //
        // governor.execute(proposalId);
        //
        // ghost_totalReturned += ghost_proposalStake[proposalId];
        // ghost_proposalFinalized[proposalId] = true;
    }

    /**
     * @notice Handler for claimStake() - claims stake after proposal ends
     * @dev Slashes 10% if proposal failed, returns full if passed
     *
     * Ghost updates (on failure):
     * - ghost_totalSlashed += stake * 10%
     * - ghost_totalReturned += stake * 90%
     */
    function handler_claimStake(uint256 proposalIdSeed) external countCall("claimStake") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound proposalId
        // 2. Check proposal is finalized (Executed or Defeated or Cancelled)
        // 3. Check stake not already claimed
        // 4. Claim stake
        // 5. Update ghost variables based on outcome
        //
        // uint256 proposalId = bound(proposalIdSeed, 1, governor.proposalCount());
        // ProposalState state = governor.state(proposalId);
        //
        // if (state == ProposalState.Defeated || state == ProposalState.Cancelled) {
        //     uint256 stake = ghost_proposalStake[proposalId];
        //     uint256 slashAmount = stake / 10; // 10%
        //     ghost_totalSlashed += slashAmount;
        //     ghost_totalReturned += stake - slashAmount;
        // } else if (state == ProposalState.Executed) {
        //     ghost_totalReturned += ghost_proposalStake[proposalId];
        // }
        //
        // ghost_proposalFinalized[proposalId] = true;
    }

    /**
     * @notice Handler for cancel() - proposer cancels their proposal
     * @dev Only proposer can cancel, triggers 10% slash
     */
    function handler_cancel(
        uint256 actorSeed,
        uint256 proposalIdSeed
    ) external useActor(actorSeed) countCall("cancel") {
        // TODO: Implement after SOL deploys contracts
    }

    /**
     * @notice Handler for warp - advances time
     * @dev Used to move through proposal lifecycle
     */
    function handler_warp(uint256 secondsSeed) external countCall("warp") {
        uint256 seconds_ = bound(secondsSeed, 1, 7 days);
        vm.warp(block.timestamp + seconds_);
    }

    /**
     * @notice Handler for roll - advances blocks
     * @dev Used to move through voting periods
     */
    function handler_roll(uint256 blocksSeed) external countCall("roll") {
        uint256 blocks = bound(blocksSeed, 1, 1000);
        vm.roll(block.number + blocks);
    }

    // ============ View Functions for Invariants ============

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function callSummary() external view {
        console.log("--- Call Summary ---");
        console.log("propose:", calls["propose"]);
        console.log("vote:", calls["vote"]);
        console.log("execute:", calls["execute"]);
        console.log("claimStake:", calls["claimStake"]);
        console.log("cancel:", calls["cancel"]);
        console.log("warp:", calls["warp"]);
        console.log("roll:", calls["roll"]);
    }
}
