// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Governance} from "../src/Governance.sol";

/**
 * @title GovernanceTest
 * @notice Test suite for the Governance contract
 * @dev Uses Foundry's Test framework for testing
 *
 * ## Test Categories
 * - Unit tests: Test individual functions in isolation
 * - Integration tests: Test function interactions
 * - Fuzz tests: Test with random inputs
 * - Invariant tests: Test protocol-wide invariants
 */
contract GovernanceTest is Test {
    // ============ State Variables ============

    Governance public governance;

    address public owner;
    address public guardian;
    address public proposer;
    address public voter1;
    address public voter2;
    address public nonAuthorized;

    uint256 public constant VOTING_PERIOD = 1 weeks;
    uint256 public constant VOTING_DELAY = 1 days;

    // ============ Events (for testing) ============

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 startTime,
        uint256 endTime
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );

    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    // ============ Setup ============

    /**
     * @notice Sets up the test environment before each test
     * @dev Creates test accounts and deploys the Governance contract
     */
    function setUp() public {
        // Create test accounts
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        nonAuthorized = makeAddr("nonAuthorized");

        // Deploy governance contract
        vm.prank(owner);
        governance = new Governance(owner, guardian, VOTING_PERIOD, VOTING_DELAY);

        // Grant proposer role
        vm.prank(owner);
        governance.setProposer(proposer, true);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsOwner() public view {
        assertEq(governance.owner(), owner);
    }

    function test_Constructor_SetsGuardian() public view {
        assertEq(governance.guardian(), guardian);
    }

    function test_Constructor_SetsVotingPeriod() public view {
        assertEq(governance.votingPeriod(), VOTING_PERIOD);
    }

    function test_Constructor_SetsVotingDelay() public view {
        assertEq(governance.votingDelay(), VOTING_DELAY);
    }

    function test_Constructor_OwnerIsProposer() public view {
        assertTrue(governance.isProposer(owner));
    }

    function test_Constructor_RevertIf_ZeroOwner() public {
        vm.expectRevert(Governance.ZeroAddress.selector);
        new Governance(address(0), guardian, VOTING_PERIOD, VOTING_DELAY);
    }

    function test_Constructor_RevertIf_ZeroGuardian() public {
        vm.expectRevert(Governance.ZeroAddress.selector);
        new Governance(owner, address(0), VOTING_PERIOD, VOTING_DELAY);
    }

    // ============ Propose Tests ============

    /**
     * @notice Test that a proposer can create a proposal
     *
     * INVARIANT HOOK: proposalCount increases by 1
     */
    function test_Propose_Success() public {
        // TODO: Implement full test
        // - Create proposal
        // - Verify proposal stored correctly
        // - Verify event emitted

        address[] memory targets = new address[](1);
        targets[0] = address(this);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        uint256 proposalCountBefore = governance.proposalCount();

        vm.prank(proposer);
        uint256 proposalId = governance.propose(targets, values, calldatas, "Test Proposal");

        assertEq(governance.proposalCount(), proposalCountBefore + 1);
        assertEq(proposalId, 1);
    }

    function test_Propose_RevertIf_NotProposer() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(nonAuthorized);
        vm.expectRevert(Governance.NotProposer.selector);
        governance.propose(targets, values, calldatas, "Test Proposal");
    }

    function test_Propose_RevertIf_Paused() public {
        // Pause contract
        vm.prank(guardian);
        governance.pause();

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(proposer);
        vm.expectRevert();
        governance.propose(targets, values, calldatas, "Test Proposal");
    }

    // ============ Vote Tests ============

    /**
     * @notice Test that voting works correctly
     *
     * INVARIANT HOOK: hasVoted becomes true after voting
     * INVARIANT HOOK: vote counts increase correctly
     */
    function test_Vote_Success() public {
        // TODO: Implement full test
        // - Create proposal
        // - Wait for voting to start
        // - Cast vote
        // - Verify vote recorded

        uint256 proposalId = _createTestProposal();

        // Move to voting period
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.prank(voter1);
        governance.vote(proposalId, true);

        assertTrue(governance.hasVotedOnProposal(proposalId, voter1));
    }

    function test_Vote_RevertIf_AlreadyVoted() public {
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.prank(voter1);
        governance.vote(proposalId, true);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(Governance.AlreadyVoted.selector, proposalId, voter1));
        governance.vote(proposalId, true);
    }

    function test_Vote_RevertIf_ProposalNotFound() public {
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(Governance.ProposalNotFound.selector, 999));
        governance.vote(999, true);
    }

    function test_Vote_RevertIf_VotingNotStarted() public {
        uint256 proposalId = _createTestProposal();

        // Try to vote before voting starts
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(Governance.VotingEnded.selector, proposalId));
        governance.vote(proposalId, true);
    }

    function test_Vote_RevertIf_VotingEnded() public {
        uint256 proposalId = _createTestProposal();

        // Move past voting period
        vm.warp(block.timestamp + VOTING_DELAY + VOTING_PERIOD + 1);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(Governance.VotingEnded.selector, proposalId));
        governance.vote(proposalId, true);
    }

    // ============ Execute Tests ============

    /**
     * @notice Test that execution works correctly
     *
     * INVARIANT HOOK: Proposal can only be executed once
     * INVARIANT HOOK: Proposal must have succeeded
     */
    function test_Execute_Success() public {
        // TODO: Implement full test
        // - Create proposal
        // - Vote in favor
        // - Wait for voting to end
        // - Execute proposal
        // - Verify execution

        // Create a proposal with an empty action (no targets)
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(proposer);
        uint256 proposalId = governance.propose(targets, values, calldatas, "Empty Proposal");

        // Vote in favor
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(voter1);
        governance.vote(proposalId, true);

        // Move past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        governance.execute(proposalId);

        (,,,,,bool executed) = governance.getProposal(proposalId);
        assertTrue(executed);
    }

    function test_Execute_RevertIf_VotingNotEnded() public {
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(voter1);
        governance.vote(proposalId, true);

        // Try to execute during voting
        vm.expectRevert(abi.encodeWithSelector(Governance.VotingNotEnded.selector, proposalId));
        governance.execute(proposalId);
    }

    function test_Execute_RevertIf_ProposalDefeated() public {
        uint256 proposalId = _createTestProposal();

        // Vote against
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(voter1);
        governance.vote(proposalId, false);

        // Move past voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.expectRevert();
        governance.execute(proposalId);
    }

    // ============ Pause Tests ============

    /**
     * @notice Test that pausing works correctly
     *
     * INVARIANT HOOK: Only guardian can pause
     */
    function test_Pause_Success() public {
        vm.prank(guardian);
        governance.pause();

        assertTrue(governance.paused());
    }

    function test_Pause_RevertIf_NotGuardian() public {
        vm.prank(nonAuthorized);
        vm.expectRevert(Governance.NotGuardian.selector);
        governance.pause();
    }

    function test_Unpause_Success() public {
        vm.prank(guardian);
        governance.pause();

        vm.prank(guardian);
        governance.unpause();

        assertFalse(governance.paused());
    }

    // ============ Admin Tests ============

    function test_TransferOwnership_Success() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        governance.transferOwnership(newOwner);

        assertEq(governance.owner(), newOwner);
    }

    function test_TransferOwnership_RevertIf_NotOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(nonAuthorized);
        vm.expectRevert(Governance.NotOwner.selector);
        governance.transferOwnership(newOwner);
    }

    function test_SetGuardian_Success() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(owner);
        governance.setGuardian(newGuardian);

        assertEq(governance.guardian(), newGuardian);
    }

    function test_SetProposer_Success() public {
        address newProposer = makeAddr("newProposer");

        vm.prank(owner);
        governance.setProposer(newProposer, true);

        assertTrue(governance.isProposer(newProposer));
    }

    function test_Cancel_Success() public {
        uint256 proposalId = _createTestProposal();

        vm.prank(owner);
        governance.cancel(proposalId);

        assertEq(uint256(governance.state(proposalId)), uint256(Governance.ProposalState.Cancelled));
    }

    // ============ View Function Tests ============

    function test_State_Pending() public {
        uint256 proposalId = _createTestProposal();

        assertEq(uint256(governance.state(proposalId)), uint256(Governance.ProposalState.Pending));
    }

    function test_State_Active() public {
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + VOTING_DELAY + 1);

        assertEq(uint256(governance.state(proposalId)), uint256(Governance.ProposalState.Active));
    }

    function test_State_Succeeded() public {
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(voter1);
        governance.vote(proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        assertEq(uint256(governance.state(proposalId)), uint256(Governance.ProposalState.Succeeded));
    }

    function test_State_Defeated() public {
        uint256 proposalId = _createTestProposal();

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(voter1);
        governance.vote(proposalId, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        assertEq(uint256(governance.state(proposalId)), uint256(Governance.ProposalState.Defeated));
    }

    // ============ Fuzz Tests ============

    /**
     * @notice Fuzz test for proposal creation
     * @param description Random proposal description
     */
    function testFuzz_Propose_Description(string calldata description) public {
        address[] memory targets = new address[](1);
        targets[0] = address(this);

        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(proposer);
        uint256 proposalId = governance.propose(targets, values, calldatas, description);

        assertGt(proposalId, 0);
    }

    // ============ Invariant Test Hooks ============

    /**
     * @notice Invariant: proposalCount should never decrease
     *
     * To implement invariant testing:
     * 1. Create a handler contract that calls governance functions
     * 2. Define invariant functions that check protocol state
     * 3. Use Foundry's invariant testing features
     *
     * Example invariant functions to implement:
     * - invariant_proposalCountNeverDecreases
     * - invariant_executedProposalsCannotBeReExecuted
     * - invariant_votingPeriodRespected
     * - invariant_onlyProposersCanPropose
     */

    // TODO: Implement invariant test handler
    // contract GovernanceHandler is Test {
    //     Governance governance;
    //
    //     function handler_propose() external { ... }
    //     function handler_vote() external { ... }
    //     function handler_execute() external { ... }
    // }

    // TODO: Implement invariant tests
    // function invariant_proposalCountNeverDecreases() public view {
    //     assertGe(governance.proposalCount(), previousProposalCount);
    // }

    // ============ Helper Functions ============

    /**
     * @notice Creates a test proposal with default parameters
     * @return proposalId The ID of the created proposal
     */
    function _createTestProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(this);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(proposer);
        return governance.propose(targets, values, calldatas, "Test Proposal");
    }

    /// @notice Dummy function to be called by proposals
    function dummyFunction() external pure returns (bool) {
        return true;
    }
}
