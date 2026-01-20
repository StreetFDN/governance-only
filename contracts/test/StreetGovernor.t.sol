// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KLEDToken} from "../src/KLEDToken.sol";
import {StreetGovernor} from "../src/StreetGovernor.sol";

/**
 * @title StreetGovernorTest
 * @notice Unit and fuzz tests for StreetGovernor contract
 * @dev Tests proposal creation, voting, execution, and slashing
 *
 * ## Test Categories
 * 1. Constructor and initialization
 * 2. Proposal Creation with 50K KLED Stake (STAKE-*)
 * 3. Voting (Yes/No/Abstain) Weighted by Token Balance (VOTE-*)
 * 4. 10% Slashing on Failed Proposals (SLASH-*)
 * 5. Snapshot Voting - Flash Loan Prevention (SNAP-*)
 * 6. Execution and state transitions
 * 7. Admin functions
 */
contract StreetGovernorTest is Test {
    KLEDToken public token;
    StreetGovernor public governor;

    // Actors
    address public owner;
    address public guardian;
    address public treasury;
    address public proposer;
    address public alice;
    address public bob;
    address public whale;
    address public attacker;

    // Constants
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;
    uint256 public constant PROPOSAL_STAKE = 50_000 ether;
    uint256 public constant SLASH_BPS = 1000; // 10%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // Governance parameters
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_BPS = 400; // 4%
    uint256 public constant THRESHOLD_BPS = 5000; // 50%

    // Actor balances
    uint256 public constant PROPOSER_BALANCE = 100_000 ether;
    uint256 public constant ALICE_BALANCE = 10_000 ether;
    uint256 public constant BOB_BALANCE = 25_000 ether;
    uint256 public constant WHALE_BALANCE = 10_000_000 ether;

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 snapshotTimestamp,
        uint256 startTime,
        uint256 endTime,
        uint256 stakeAmount
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        StreetGovernor.VoteType support,
        uint256 weight,
        string reason
    );

    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event StakeClaimed(uint256 indexed proposalId, address indexed proposer, uint256 amount);
    event StakeSlashed(uint256 indexed proposalId, address indexed proposer, uint256 slashedAmount, uint256 returnedAmount);

    function setUp() public {
        // Create actors
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        proposer = makeAddr("proposer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        whale = makeAddr("whale");
        attacker = makeAddr("attacker");

        // Set initial timestamp
        vm.warp(1000);

        // Deploy token
        vm.prank(owner);
        token = new KLEDToken(owner, INITIAL_SUPPLY);

        // Deploy governor
        vm.prank(owner);
        governor = new StreetGovernor(
            address(token),
            owner,
            guardian,
            treasury,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_BPS,
            THRESHOLD_BPS
        );

        // Fund actors
        vm.startPrank(owner);
        token.transfer(proposer, PROPOSER_BALANCE);
        token.transfer(alice, ALICE_BALANCE);
        token.transfer(bob, BOB_BALANCE);
        token.transfer(whale, WHALE_BALANCE);
        vm.stopPrank();

        // Setup delegations (each actor self-delegates)
        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(whale);
        token.delegate(whale);
        vm.prank(owner);
        token.delegate(owner);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsParameters() public view {
        assertEq(address(governor.token()), address(token));
        assertEq(governor.owner(), owner);
        assertEq(governor.guardian(), guardian);
        assertEq(governor.treasury(), treasury);
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.quorumBps(), QUORUM_BPS);
        assertEq(governor.thresholdBps(), THRESHOLD_BPS);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(StreetGovernor.ZeroAddress.selector);
        new StreetGovernor(address(0), owner, guardian, treasury, VOTING_DELAY, VOTING_PERIOD, QUORUM_BPS, THRESHOLD_BPS);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(StreetGovernor.ZeroAddress.selector);
        new StreetGovernor(address(token), address(0), guardian, treasury, VOTING_DELAY, VOTING_PERIOD, QUORUM_BPS, THRESHOLD_BPS);
    }

    // ============ STAKE-*: Proposal Creation Tests ============

    function test_STAKE1_ProposeRequires50KStake() public {
        // Alice has 10K KLED, cannot propose
        vm.startPrank(alice);
        token.approve(address(governor), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.InsufficientStake.selector, PROPOSAL_STAKE, ALICE_BALANCE));
        _propose();
        vm.stopPrank();
    }

    function test_STAKE2_ProposeTransfersStakeToContract() public {
        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);

        uint256 proposerBefore = token.balanceOf(proposer);
        uint256 governorBefore = token.balanceOf(address(governor));

        _propose();

        assertEq(token.balanceOf(proposer), proposerBefore - PROPOSAL_STAKE);
        assertEq(token.balanceOf(address(governor)), governorBefore + PROPOSAL_STAKE);
        vm.stopPrank();
    }

    function test_STAKE3_ProposeWithExact50K() public {
        // Give attacker exactly 50K
        vm.prank(owner);
        token.transfer(attacker, PROPOSAL_STAKE);

        vm.startPrank(attacker);
        token.delegate(attacker);
        token.approve(address(governor), type(uint256).max);

        uint256 proposalId = _propose();
        assertEq(proposalId, 1);
        vm.stopPrank();
    }

    function test_STAKE4_ProposeFailsWithInsufficientApproval() public {
        vm.startPrank(proposer);
        // No approval given
        vm.expectRevert(); // ERC20 insufficient allowance
        _propose();
        vm.stopPrank();
    }

    function test_STAKE5_MultipleProposalsRequireMultipleStakes() public {
        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);

        _propose();
        assertEq(token.balanceOf(proposer), PROPOSER_BALANCE - PROPOSAL_STAKE);

        // Can create second proposal (exactly 50K left)
        _propose();
        assertEq(token.balanceOf(proposer), 0);

        // Cannot create third proposal (0 tokens left)
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.InsufficientStake.selector, PROPOSAL_STAKE, 0));
        _propose();
        vm.stopPrank();
    }

    function testFuzz_STAKE6_ProposeStakeEdgeCases(uint256 balance) public {
        balance = bound(balance, 1 ether, 100_000 ether);

        vm.prank(owner);
        token.transfer(attacker, balance);

        vm.startPrank(attacker);
        token.delegate(attacker);
        token.approve(address(governor), type(uint256).max);

        if (balance < PROPOSAL_STAKE) {
            vm.expectRevert(abi.encodeWithSelector(StreetGovernor.InsufficientStake.selector, PROPOSAL_STAKE, balance));
        }
        _propose();
        vm.stopPrank();
    }

    function test_STAKE7_ProposeEmitsCorrectEvent() public {
        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);

        uint256 expectedStart = block.timestamp + VOTING_DELAY;
        uint256 expectedEnd = expectedStart + VOTING_PERIOD;

        vm.expectEmit(true, true, false, false);
        emit ProposalCreated(1, proposer, "Test Title", new address[](0), new uint256[](0), new bytes[](0), block.timestamp, expectedStart, expectedEnd, PROPOSAL_STAKE);

        _propose();
        vm.stopPrank();
    }

    // ============ VOTE-*: Voting Tests ============

    function test_VOTE1_VoteWeightedBySnapshotBalance() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(alice);
        governor.vote(proposalId, 1); // For

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        assertEq(forVotes, ALICE_BALANCE);
    }

    function test_VOTE2_VoteYesIncreasesForVotes() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(alice);
        governor.vote(proposalId, 1); // For

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        assertEq(forVotes, ALICE_BALANCE);
    }

    function test_VOTE3_VoteNoIncreasesAgainstVotes() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(alice);
        governor.vote(proposalId, 0); // Against

        (,,,, uint256 againstVotes,,,,) = governor.getProposal(proposalId);
        assertEq(againstVotes, ALICE_BALANCE);
    }

    function test_VOTE4_VoteAbstainIncreasesAbstainVotes() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(alice);
        governor.vote(proposalId, 2); // Abstain

        (,,,,, uint256 abstainVotes,,,) = governor.getProposal(proposalId);
        assertEq(abstainVotes, ALICE_BALANCE);
    }

    function test_VOTE5_CannotVoteTwice() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.startPrank(alice);
        governor.vote(proposalId, 1); // For

        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.AlreadyVoted.selector, proposalId, alice));
        governor.vote(proposalId, 1);
        vm.stopPrank();
    }

    function test_VOTE6_CannotVoteAfterVotingPeriod() public {
        uint256 proposalId = _createProposal();
        _advancePastVoting();

        (,,,,,, uint256 startTime, uint256 endTime,) = governor.getProposal(proposalId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.VotingEnded.selector, proposalId, endTime));
        governor.vote(proposalId, 1);
    }

    function test_VOTE7_CannotVoteBeforeVotingDelay() public {
        uint256 proposalId = _createProposal();
        // Don't advance time

        (,,,,,, uint256 startTime,,) = governor.getProposal(proposalId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.VotingNotStarted.selector, proposalId, startTime));
        governor.vote(proposalId, 1);
    }

    function test_VOTE8_ZeroBalanceCannotVote() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.NoVotingPower.selector, attacker, proposalId));
        governor.vote(proposalId, 1);
    }

    function test_VOTE9_DelegatedVotesCount() public {
        // Alice delegates to Bob
        vm.prank(alice);
        token.delegate(bob);

        // Need to advance time for delegation to be checkpointed
        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Bob votes with his own + Alice's delegated power
        vm.prank(bob);
        governor.vote(proposalId, 1);

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        assertEq(forVotes, ALICE_BALANCE + BOB_BALANCE);
    }

    function test_VOTE11_HasVotedReturnsCorrectly() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        assertFalse(governor.hasVoted(proposalId, alice));

        vm.prank(alice);
        governor.vote(proposalId, 1);

        assertTrue(governor.hasVoted(proposalId, alice));
    }

    // ============ SLASH-*: Slashing Tests ============

    function test_SLASH1_FailedProposalSlashes10Percent() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Vote against with whale to defeat
        vm.prank(whale);
        governor.vote(proposalId, 0); // Against

        _advancePastVoting();

        // Verify defeated
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Defeated));

        uint256 proposerBefore = token.balanceOf(proposer);
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(proposer);
        governor.claimStakeAfterDefeat(proposalId);

        uint256 slashAmount = (PROPOSAL_STAKE * SLASH_BPS) / BPS_DENOMINATOR;
        uint256 returnAmount = PROPOSAL_STAKE - slashAmount;

        assertEq(token.balanceOf(proposer), proposerBefore + returnAmount);
        assertEq(token.balanceOf(treasury), treasuryBefore + slashAmount);
    }

    function test_SLASH2_SlashedTokensGoToTreasury() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 0);

        _advancePastVoting();

        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(proposer);
        governor.claimStakeAfterDefeat(proposalId);

        uint256 slashAmount = (PROPOSAL_STAKE * SLASH_BPS) / BPS_DENOMINATOR;
        assertEq(token.balanceOf(treasury), treasuryBefore + slashAmount);
    }

    function test_SLASH3_PassedProposalReturnsFullStake() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Vote for with whale to pass
        vm.prank(whale);
        governor.vote(proposalId, 1); // For

        _advancePastVoting();

        // Verify succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Succeeded));

        uint256 proposerBefore = token.balanceOf(proposer);

        // Execute returns stake
        governor.execute(proposalId);

        assertEq(token.balanceOf(proposer), proposerBefore + PROPOSAL_STAKE);
    }

    function test_SLASH4_CanceledProposalReturnsFullStake() public {
        uint256 proposalId = _createProposal();
        // Cancel before voting starts (no slash on cancel)

        uint256 proposerBefore = token.balanceOf(proposer);

        vm.prank(proposer);
        governor.cancel(proposalId);

        assertEq(token.balanceOf(proposer), proposerBefore + PROPOSAL_STAKE);
    }

    function test_SLASH6_SlashingEmitsEvent() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 0);

        _advancePastVoting();

        uint256 slashAmount = (PROPOSAL_STAKE * SLASH_BPS) / BPS_DENOMINATOR;
        uint256 returnAmount = PROPOSAL_STAKE - slashAmount;

        vm.expectEmit(true, true, false, true);
        emit StakeSlashed(proposalId, proposer, slashAmount, returnAmount);

        vm.prank(proposer);
        governor.claimStakeAfterDefeat(proposalId);
    }

    function testFuzz_SLASH7_SlashingCalculation(uint256 stake) public pure {
        stake = bound(stake, 1 ether, 10_000_000 ether);

        uint256 expectedSlash = (stake * SLASH_BPS) / BPS_DENOMINATOR;
        uint256 expectedReturn = stake - expectedSlash;

        // Verify the return amount is correct
        assertEq(expectedSlash + expectedReturn, stake);
        // Verify slash is approximately 10% (within rounding)
        assertTrue(expectedSlash <= stake / 10 + 1);
        assertTrue(expectedSlash >= stake / 10);
    }

    function test_SLASH8_CannotClaimStakeTwice() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 0);

        _advancePastVoting();

        vm.startPrank(proposer);
        governor.claimStakeAfterDefeat(proposalId);

        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.StakeAlreadyClaimed.selector, proposalId));
        governor.claimStakeAfterDefeat(proposalId);
        vm.stopPrank();
    }

    // ============ SNAP-*: Snapshot Tests ============

    function test_SNAP1_SnapshotTakenAtProposalCreation() public {
        uint256 timestampBefore = block.timestamp;
        uint256 proposalId = _createProposal();

        // The snapshot is at proposal creation time
        // We can verify by checking voting power
        _advanceToVoting();

        vm.prank(alice);
        governor.vote(proposalId, 1);

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        // Alice's voting power at snapshot should be ALICE_BALANCE
        assertEq(forVotes, ALICE_BALANCE);
    }

    function test_SNAP2_TokensAcquiredAfterSnapshotNoVotes() public {
        uint256 proposalId = _createProposal();

        // Advance time so transfers happen AFTER snapshot
        vm.warp(block.timestamp + 1);

        // Attacker acquires tokens AFTER snapshot
        vm.prank(owner);
        token.transfer(attacker, 500_000 ether);

        vm.prank(attacker);
        token.delegate(attacker);

        _advanceToVoting();

        // Attacker should have no voting power (balance at snapshot was 0)
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.NoVotingPower.selector, attacker, proposalId));
        governor.vote(proposalId, 1);
    }

    function test_SNAP3_TokensSoldAfterSnapshotStillVote() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Alice sells all tokens after snapshot
        vm.prank(alice);
        token.transfer(bob, ALICE_BALANCE);

        // Alice can still vote with her snapshot balance
        vm.prank(alice);
        governor.vote(proposalId, 1);

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        assertEq(forVotes, ALICE_BALANCE);
    }

    function testFuzz_SNAP4_FlashLoanCannotInfluenceVote(uint256 flashAmount) public {
        flashAmount = bound(flashAmount, 1 ether, 10_000_000 ether);

        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Simulate flash loan: borrow tokens
        vm.prank(owner);
        token.transfer(attacker, flashAmount);

        vm.prank(attacker);
        token.delegate(attacker);

        // Attacker cannot vote (no balance at snapshot)
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.NoVotingPower.selector, attacker, proposalId));
        governor.vote(proposalId, 1);
    }

    function test_SNAP6_DelegationAtSnapshotApplies() public {
        // Alice delegates to Bob before proposal
        vm.prank(alice);
        token.delegate(bob);

        vm.warp(block.timestamp + 1);

        uint256 proposalId = _createProposal();
        _advanceToVoting();

        // Alice changes delegation after snapshot
        vm.prank(alice);
        token.delegate(alice);

        // Bob should still have Alice's votes (from snapshot)
        vm.prank(bob);
        governor.vote(proposalId, 1);

        (,,, uint256 forVotes,,,,,) = governor.getProposal(proposalId);
        assertEq(forVotes, ALICE_BALANCE + BOB_BALANCE);

        // Alice should have no voting power (was delegated at snapshot)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.NoVotingPower.selector, alice, proposalId));
        governor.vote(proposalId, 1);
    }

    // ============ State Transition Tests ============

    function test_StatePending() public {
        uint256 proposalId = _createProposal();
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Pending));
    }

    function test_StateActive() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Active));
    }

    function test_StateCanceled() public {
        uint256 proposalId = _createProposal();
        vm.prank(proposer);
        governor.cancel(proposalId);
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Canceled));
    }

    function test_StateDefeated_NoVotes() public {
        uint256 proposalId = _createProposal();
        _advancePastVoting();
        // No votes = defeated (quorum not met)
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Defeated));
    }

    function test_StateDefeated_AgainstWins() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 0); // Against

        _advancePastVoting();
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Defeated));
    }

    function test_StateSucceeded() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 1); // For

        _advancePastVoting();
        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Succeeded));
    }

    function test_StateExecuted() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 1);

        _advancePastVoting();
        governor.execute(proposalId);

        assertEq(uint256(governor.state(proposalId)), uint256(StreetGovernor.ProposalState.Executed));
    }

    // ============ Execution Tests ============

    function test_ExecuteCallsTargets() public {
        // Create a proposal that calls a mock target
        MockTarget target = new MockTarget();

        address[] memory targets = new address[](1);
        targets[0] = address(target);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("doSomething()");

        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);
        uint256 proposalId = governor.propose("Test", "Description", targets, values, calldatas);
        vm.stopPrank();

        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 1);

        _advancePastVoting();

        assertFalse(target.called());
        governor.execute(proposalId);
        assertTrue(target.called());
    }

    function test_ExecuteCannotBeCalledTwice() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(whale);
        governor.vote(proposalId, 1);

        _advancePastVoting();
        governor.execute(proposalId);

        vm.expectRevert(abi.encodeWithSelector(
            StreetGovernor.InvalidProposalState.selector,
            proposalId,
            StreetGovernor.ProposalState.Succeeded,
            StreetGovernor.ProposalState.Executed
        ));
        governor.execute(proposalId);
    }

    // ============ Cancel Tests ============

    function test_CancelOnlyByProposerOrOwner() public {
        uint256 proposalId = _createProposal();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StreetGovernor.NotProposer.selector, proposalId, alice));
        governor.cancel(proposalId);

        // Proposer can cancel
        vm.prank(proposer);
        governor.cancel(proposalId);
    }

    function test_CancelOnlyBeforeVoting() public {
        uint256 proposalId = _createProposal();
        _advanceToVoting();

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(
            StreetGovernor.InvalidProposalState.selector,
            proposalId,
            StreetGovernor.ProposalState.Pending,
            StreetGovernor.ProposalState.Active
        ));
        governor.cancel(proposalId);
    }

    // ============ Admin Tests ============

    function test_SetVotingDelay() public {
        vm.prank(owner);
        governor.setVotingDelay(2 days);
        assertEq(governor.votingDelay(), 2 days);
    }

    function test_SetVotingPeriod() public {
        vm.prank(owner);
        governor.setVotingPeriod(14 days);
        assertEq(governor.votingPeriod(), 14 days);
    }

    function test_SetQuorum() public {
        vm.prank(owner);
        governor.setQuorum(500); // 5%
        assertEq(governor.quorumBps(), 500);
    }

    function test_SetThreshold() public {
        vm.prank(owner);
        governor.setThreshold(6000); // 60%
        assertEq(governor.thresholdBps(), 6000);
    }

    function test_Pause() public {
        vm.prank(guardian);
        governor.pause();
        assertTrue(governor.paused());
    }

    function test_PausedCannotPropose() public {
        vm.prank(guardian);
        governor.pause();

        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);
        vm.expectRevert("Paused");
        _propose();
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _propose() internal returns (uint256) {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);
        return governor.propose("Test Title", "Test Description", targets, values, calldatas);
    }

    function _createProposal() internal returns (uint256) {
        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);
        uint256 proposalId = _propose();
        vm.stopPrank();
        return proposalId;
    }

    function _advanceToVoting() internal {
        vm.warp(block.timestamp + VOTING_DELAY + 1);
    }

    function _advancePastVoting() internal {
        vm.warp(block.timestamp + VOTING_DELAY + VOTING_PERIOD + 1);
    }
}

/// @notice Mock contract for testing execution
contract MockTarget {
    bool public called;

    function doSomething() external {
        called = true;
    }
}
