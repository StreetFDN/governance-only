// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title EditHandler
 * @notice Handler contract for invariant testing of EditSuggestions
 * @dev Wraps edit suggestion functions with bounded inputs for stateful fuzzing
 *
 * ## Edit System Requirements
 * - proposeEdit requires 500 KLED stake
 * - 48h window for submitting edits after proposal creation
 * - 72h voting window for edit suggestions
 * - Stake returned on acceptance, slashed on rejection
 *
 * ## Invariants to Test
 * - INV-EDIT-1: editVotes <= snapshotSupply
 * - INV-EDIT-2: editStakeEscrow == sum(activeSuggestionStakes)
 * - INV-EDIT-3: Edits only during 48h window
 * - INV-EDIT-4: Edit voting only during 72h window
 */
contract EditHandler is CommonBase, StdCheats, StdUtils {
    // ============ Constants ============

    uint256 public constant EDIT_STAKE = 500e18; // 500 KLED
    uint256 public constant EDIT_WINDOW = 48 hours;
    uint256 public constant EDIT_VOTING_WINDOW = 72 hours;

    // ============ Contracts (set after SOL deploys) ============

    // IEditSuggestions public editContract;
    // IKLEDToken public token;
    // IStreetGovernor public governor;

    // ============ Ghost Variables ============

    uint256 public ghost_totalEditsProposed;
    uint256 public ghost_totalEditStaked;
    uint256 public ghost_totalEditSlashed;
    uint256 public ghost_totalEditReturned;
    uint256 public ghost_totalEditVotesCast;

    mapping(uint256 => uint256) public ghost_suggestionStake;
    mapping(uint256 => bool) public ghost_suggestionFinalized;

    // ============ Actors ============

    address[] public actors;
    address internal currentActor;

    // ============ Call Counters ============

    mapping(bytes32 => uint256) public calls;

    // ============ Constructor ============

    constructor() {
        // TODO: Accept contract addresses after SOL deploys
        // editContract = IEditSuggestions(_editContract);
        // token = IKLEDToken(_token);
        // governor = IStreetGovernor(_governor);

        // Setup actors
        actors.push(makeAddr("edit_alice"));
        actors.push(makeAddr("edit_bob"));
        actors.push(makeAddr("edit_editor"));
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
     * @notice Handler for proposeEdit() - suggests an edit to a proposal
     * @dev Requires 500 KLED stake, only during 48h window
     *
     * Ghost updates:
     * - ghost_totalEditsProposed++
     * - ghost_totalEditStaked += EDIT_STAKE
     * - ghost_suggestionStake[suggestionId] = EDIT_STAKE
     */
    function handler_proposeEdit(
        uint256 actorSeed,
        uint256 proposalIdSeed,
        bytes32 originalHash,
        string calldata proposedText
    ) external useActor(actorSeed) countCall("proposeEdit") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound proposalId to valid proposals
        // 2. Check we're within 48h window
        // 3. Check actor has 500 KLED and approved
        // 4. Submit edit
        // 5. Update ghost variables
        //
        // uint256 proposalId = bound(proposalIdSeed, 1, governor.proposalCount());
        //
        // // Check edit window
        // uint256 proposalCreatedAt = governor.proposalCreatedAt(proposalId);
        // if (block.timestamp > proposalCreatedAt + EDIT_WINDOW) return;
        //
        // // Check balance and approval
        // if (token.balanceOf(currentActor) < EDIT_STAKE) return;
        // if (token.allowance(currentActor, address(editContract)) < EDIT_STAKE) {
        //     token.approve(address(editContract), type(uint256).max);
        // }
        //
        // uint256 suggestionId = editContract.proposeEdit(proposalId, originalHash, proposedText);
        //
        // ghost_totalEditsProposed++;
        // ghost_totalEditStaked += EDIT_STAKE;
        // ghost_suggestionStake[suggestionId] = EDIT_STAKE;
    }

    /**
     * @notice Handler for voteOnSuggestion() - votes on an edit suggestion
     * @dev Only during 72h voting window
     *
     * Ghost updates:
     * - ghost_totalEditVotesCast += weight
     */
    function handler_voteOnSuggestion(
        uint256 actorSeed,
        uint256 suggestionIdSeed,
        bool support
    ) external useActor(actorSeed) countCall("voteOnEdit") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound suggestionId
        // 2. Check we're within 72h voting window
        // 3. Check actor has voting power
        // 4. Cast vote
        // 5. Update ghost variables
        //
        // uint256 suggestionId = bound(suggestionIdSeed, 1, editContract.suggestionCount());
        //
        // // Check voting window
        // uint256 suggestionCreatedAt = editContract.suggestionCreatedAt(suggestionId);
        // if (block.timestamp > suggestionCreatedAt + EDIT_VOTING_WINDOW) return;
        //
        // // Check hasn't voted
        // if (editContract.hasVotedOnSuggestion(suggestionId, currentActor)) return;
        //
        // uint256 weight = token.getPastVotes(currentActor, editContract.suggestionSnapshot(suggestionId));
        // if (weight == 0) return;
        //
        // editContract.voteOnSuggestion(suggestionId, support);
        //
        // ghost_totalEditVotesCast += weight;
    }

    /**
     * @notice Handler for finalizeSuggestion() - finalizes an edit after voting
     * @dev Stakes returned/slashed based on outcome
     *
     * Ghost updates (on rejection):
     * - ghost_totalEditSlashed += stake
     * Ghost updates (on acceptance):
     * - ghost_totalEditReturned += stake
     */
    function handler_finalizeSuggestion(uint256 suggestionIdSeed) external countCall("finalizeSuggestion") {
        // TODO: Implement after SOL deploys contracts
        //
        // Pseudocode:
        // 1. Bound suggestionId
        // 2. Check voting window ended
        // 3. Finalize suggestion
        // 4. Update ghost variables based on outcome
        //
        // uint256 suggestionId = bound(suggestionIdSeed, 1, editContract.suggestionCount());
        //
        // editContract.finalizeSuggestion(suggestionId);
        //
        // bool accepted = editContract.suggestionAccepted(suggestionId);
        // uint256 stake = ghost_suggestionStake[suggestionId];
        //
        // if (accepted) {
        //     ghost_totalEditReturned += stake;
        // } else {
        //     ghost_totalEditSlashed += stake;
        // }
        //
        // ghost_suggestionFinalized[suggestionId] = true;
    }

    // ============ View Functions for Invariants ============

    function getActors() external view returns (address[] memory) {
        return actors;
    }

    function callSummary() external view {
        console.log("--- Edit Call Summary ---");
        console.log("proposeEdit:", calls["proposeEdit"]);
        console.log("voteOnEdit:", calls["voteOnEdit"]);
        console.log("finalizeSuggestion:", calls["finalizeSuggestion"]);
    }
}
