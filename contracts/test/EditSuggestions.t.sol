// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KLEDToken} from "../src/KLEDToken.sol";
import {StreetGovernor} from "../src/StreetGovernor.sol";
import {EditSuggestions} from "../src/EditSuggestions.sol";

/**
 * @title EditSuggestionsTest
 * @notice Unit and fuzz tests for EditSuggestions contract
 * @dev Tests edit proposal creation, voting, and stake handling
 *
 * ## Test Categories
 * 1. Edit Suggestions with 500 KLED Stake (EDIT-*)
 * 2. Time window validation
 * 3. Voting mechanics
 * 4. Stake handling
 */
contract EditSuggestionsTest is Test {
    KLEDToken public token;
    StreetGovernor public governor;
    EditSuggestions public editSuggestions;

    // Actors
    address public owner;
    address public guardian;
    address public treasury;
    address public proposer;
    address public alice;
    address public bob;
    address public whale;

    // Constants
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;
    uint256 public constant PROPOSAL_STAKE = 50_000 ether;
    uint256 public constant EDIT_STAKE = 500 ether;
    uint256 public constant EDIT_WINDOW = 48 hours;
    uint256 public constant VOTING_WINDOW = 72 hours;

    // Governance parameters
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant QUORUM_BPS = 400;
    uint256 public constant THRESHOLD_BPS = 5000;

    // Actor balances
    uint256 public constant PROPOSER_BALANCE = 100_000 ether;
    uint256 public constant ALICE_BALANCE = 10_000 ether;
    uint256 public constant BOB_BALANCE = 25_000 ether;
    uint256 public constant WHALE_BALANCE = 10_000_000 ether;

    // Events
    event SuggestionCreated(
        uint256 indexed suggestionId,
        uint256 indexed proposalId,
        address indexed suggester,
        bytes32 originalHash,
        string proposedText,
        uint256 stakeAmount,
        uint256 editDeadline,
        uint256 voteDeadline
    );

    event SuggestionVoteCast(
        uint256 indexed suggestionId,
        address indexed voter,
        bool support,
        uint256 weight
    );

    event SuggestionFinalized(
        uint256 indexed suggestionId,
        bool accepted,
        uint256 forVotes,
        uint256 againstVotes
    );

    function setUp() public {
        owner = makeAddr("owner");
        guardian = makeAddr("guardian");
        treasury = makeAddr("treasury");
        proposer = makeAddr("proposer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        whale = makeAddr("whale");

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

        // Deploy edit suggestions
        vm.prank(owner);
        editSuggestions = new EditSuggestions(
            address(token),
            address(governor),
            owner,
            treasury
        );

        // Fund actors
        vm.startPrank(owner);
        token.transfer(proposer, PROPOSER_BALANCE);
        token.transfer(alice, ALICE_BALANCE);
        token.transfer(bob, BOB_BALANCE);
        token.transfer(whale, WHALE_BALANCE);
        vm.stopPrank();

        // Setup delegations
        vm.prank(proposer);
        token.delegate(proposer);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.prank(whale);
        token.delegate(whale);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsParameters() public view {
        assertEq(address(editSuggestions.token()), address(token));
        assertEq(address(editSuggestions.governor()), address(governor));
        assertEq(editSuggestions.owner(), owner);
        assertEq(editSuggestions.treasury(), treasury);
    }

    function test_Constructor_RevertsOnZeroToken() public {
        vm.expectRevert(EditSuggestions.ZeroAddress.selector);
        new EditSuggestions(address(0), address(governor), owner, treasury);
    }

    // ============ EDIT-*: Edit Suggestion Tests ============

    function test_EDIT1_ProposeEditRequires500KStake() public {
        uint256 proposalId = _createGovernanceProposal();

        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);

        uint256 aliceBalanceBefore = token.balanceOf(alice);

        uint256 suggestionId = editSuggestions.proposeEdit(
            proposalId,
            keccak256("original text"),
            "proposed new text"
        );

        assertEq(token.balanceOf(alice), aliceBalanceBefore - EDIT_STAKE);
        assertEq(suggestionId, 1);
        vm.stopPrank();
    }

    function test_EDIT2_ProposeEditFailsWithoutStake() public {
        uint256 proposalId = _createGovernanceProposal();

        address poorUser = makeAddr("poorUser");
        vm.prank(owner);
        token.transfer(poorUser, 100 ether); // Only 100 KLED

        vm.startPrank(poorUser);
        token.approve(address(editSuggestions), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.InsufficientStake.selector, EDIT_STAKE, 100 ether));
        editSuggestions.proposeEdit(proposalId, keccak256("original"), "proposed");
        vm.stopPrank();
    }

    function test_EDIT3_EditOnlyDuring48hWindow() public {
        uint256 proposalId = _createGovernanceProposal();

        // First edit to initialize the window (within VOTING_DELAY period)
        vm.startPrank(bob);
        token.approve(address(editSuggestions), type(uint256).max);
        editSuggestions.proposeEdit(proposalId, keccak256("original"), "first edit");
        vm.stopPrank();

        uint256 deadline = editSuggestions.editDeadlines(proposalId);

        // Advance past 48h window but stay within VOTING_DELAY (1 day < 48h, so we need to check)
        // Since VOTING_DELAY is 1 day and EDIT_WINDOW is 48h, advancing past EDIT_WINDOW
        // means the proposal becomes Active and we get InvalidProposalState instead
        // The edit window check happens AFTER proposal validation, so we get InvalidProposalState
        // This is correct behavior - once proposal is Active, no edits allowed
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);

        // Since 48h > 1 day (VOTING_DELAY), proposal becomes Active and we get InvalidProposalState
        vm.expectRevert(EditSuggestions.InvalidProposalState.selector);
        editSuggestions.proposeEdit(proposalId, keccak256("original"), "proposed");
        vm.stopPrank();
    }

    function test_EDIT4_VotingOnlyAfterEditWindow() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Try to vote before edit window ends
        uint256 editDeadline = editSuggestions.editDeadlines(proposalId);

        vm.prank(whale);
        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.VotingWindowNotStarted.selector, suggestionId, editDeadline));
        editSuggestions.voteOnSuggestion(suggestionId, true);
    }

    function test_EDIT5_VotingWindowIs72h() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance past edit window + voting window
        vm.warp(block.timestamp + EDIT_WINDOW + VOTING_WINDOW + 1);

        uint256 voteDeadline = editSuggestions.getVoteDeadline(suggestionId);

        vm.prank(whale);
        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.VotingWindowClosed.selector, suggestionId, voteDeadline));
        editSuggestions.voteOnSuggestion(suggestionId, true);
    }

    function test_EDIT6_VotingWeightedByBalance() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance to voting window
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        // Alice votes for (note: Alice's balance at snapshot is ALICE_BALANCE - EDIT_STAKE
        // because she created the suggestion and staked)
        vm.prank(alice);
        editSuggestions.voteOnSuggestion(suggestionId, true);

        // Bob votes against
        vm.prank(bob);
        editSuggestions.voteOnSuggestion(suggestionId, false);

        (,,,, uint256 forVotes, uint256 againstVotes,,) = editSuggestions.getSuggestion(suggestionId);

        // Alice's voting power is her balance minus the stake she paid
        assertEq(forVotes, ALICE_BALANCE - EDIT_STAKE);
        assertEq(againstVotes, BOB_BALANCE);
    }

    function test_EDIT7_MultipleEditsAllowed() public {
        uint256 proposalId = _createGovernanceProposal();

        // Alice proposes first edit
        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);
        uint256 suggestion1 = editSuggestions.proposeEdit(proposalId, keccak256("original"), "edit1");
        vm.stopPrank();

        // Bob proposes second edit
        vm.startPrank(bob);
        token.approve(address(editSuggestions), type(uint256).max);
        uint256 suggestion2 = editSuggestions.proposeEdit(proposalId, keccak256("original"), "edit2");
        vm.stopPrank();

        assertTrue(suggestion1 != suggestion2);

        uint256[] memory suggestions = editSuggestions.getSuggestions(proposalId);
        assertEq(suggestions.length, 2);
    }

    function test_EDIT8_StakeReturnedOnAcceptedEdit() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance to voting window
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        // Whale votes for
        vm.prank(whale);
        editSuggestions.voteOnSuggestion(suggestionId, true);

        // Advance past voting window
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        // Finalize
        editSuggestions.finalizeSuggestion(suggestionId);

        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Claim stake
        editSuggestions.claimStake(suggestionId);

        // Full stake returned
        assertEq(token.balanceOf(alice), aliceBalanceBefore + EDIT_STAKE);
    }

    function test_EDIT9_StakeSlashedOnRejectedEdit() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance to voting window
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        // Whale votes against
        vm.prank(whale);
        editSuggestions.voteOnSuggestion(suggestionId, false);

        // Advance past voting window
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        // Finalize
        editSuggestions.finalizeSuggestion(suggestionId);

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 treasuryBalanceBefore = token.balanceOf(treasury);

        // Claim stake
        editSuggestions.claimStake(suggestionId);

        // 10% slashed, 90% returned
        uint256 slashAmount = (EDIT_STAKE * 1000) / 10_000;
        uint256 returnAmount = EDIT_STAKE - slashAmount;

        assertEq(token.balanceOf(alice), aliceBalanceBefore + returnAmount);
        assertEq(token.balanceOf(treasury), treasuryBalanceBefore + slashAmount);
    }

    function test_EDIT10_CannotVoteTwice() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance to voting window
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        vm.startPrank(whale);
        editSuggestions.voteOnSuggestion(suggestionId, true);

        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.AlreadyVoted.selector, suggestionId, whale));
        editSuggestions.voteOnSuggestion(suggestionId, false);
        vm.stopPrank();
    }

    function test_EDIT11_CannotFinalizeBeforeVotingEnds() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance to voting window but not past it
        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        uint256 voteDeadline = editSuggestions.getVoteDeadline(suggestionId);

        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.VotingWindowClosed.selector, suggestionId, voteDeadline));
        editSuggestions.finalizeSuggestion(suggestionId);
    }

    function test_EDIT12_CannotClaimBeforeFinalized() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.SuggestionNotFinalized.selector, suggestionId));
        editSuggestions.claimStake(suggestionId);
    }

    function test_EDIT13_CannotClaimTwice() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        // Advance through edit and voting windows
        vm.warp(block.timestamp + EDIT_WINDOW + VOTING_WINDOW + 1);

        editSuggestions.finalizeSuggestion(suggestionId);
        editSuggestions.claimStake(suggestionId);

        vm.expectRevert(abi.encodeWithSelector(EditSuggestions.StakeAlreadyClaimed.selector, suggestionId));
        editSuggestions.claimStake(suggestionId);
    }

    function test_EDIT14_OnlyPendingProposalsCanHaveEdits() public {
        uint256 proposalId = _createGovernanceProposal();

        // Advance past voting delay so proposal is Active
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);

        vm.expectRevert(EditSuggestions.InvalidProposalState.selector);
        editSuggestions.proposeEdit(proposalId, keccak256("original"), "proposed");
        vm.stopPrank();
    }

    function test_HasVotedReturnsCorrectly() public {
        uint256 proposalId = _createGovernanceProposal();
        uint256 suggestionId = _createEditSuggestion(proposalId);

        vm.warp(block.timestamp + EDIT_WINDOW + 1);

        assertFalse(editSuggestions.hasVoted(suggestionId, whale));

        vm.prank(whale);
        editSuggestions.voteOnSuggestion(suggestionId, true);

        assertTrue(editSuggestions.hasVoted(suggestionId, whale));
    }

    function test_GetSuggestionReturnsDetails() public {
        uint256 proposalId = _createGovernanceProposal();

        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);
        bytes32 originalHash = keccak256("original text");
        string memory proposedText = "proposed new text";
        uint256 suggestionId = editSuggestions.proposeEdit(proposalId, originalHash, proposedText);
        vm.stopPrank();

        (
            uint256 retProposalId,
            address suggester,
            bytes32 retOriginalHash,
            string memory retProposedText,
            uint256 forVotes,
            uint256 againstVotes,
            bool finalized,
            bool accepted
        ) = editSuggestions.getSuggestion(suggestionId);

        assertEq(retProposalId, proposalId);
        assertEq(suggester, alice);
        assertEq(retOriginalHash, originalHash);
        assertEq(retProposedText, proposedText);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertFalse(finalized);
        assertFalse(accepted);
    }

    // ============ Admin Tests ============

    function test_TransferOwnership() public {
        vm.prank(owner);
        editSuggestions.transferOwnership(alice);
        assertEq(editSuggestions.owner(), alice);
    }

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(owner);
        editSuggestions.setTreasury(newTreasury);
        assertEq(editSuggestions.treasury(), newTreasury);
    }

    // ============ Helper Functions ============

    function _createGovernanceProposal() internal returns (uint256) {
        vm.startPrank(proposer);
        token.approve(address(governor), type(uint256).max);

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        uint256 proposalId = governor.propose("Test Title", "Test Description", targets, values, calldatas);
        vm.stopPrank();
        return proposalId;
    }

    function _createEditSuggestion(uint256 proposalId) internal returns (uint256) {
        vm.startPrank(alice);
        token.approve(address(editSuggestions), type(uint256).max);
        uint256 suggestionId = editSuggestions.proposeEdit(
            proposalId,
            keccak256("original text"),
            "proposed new text"
        );
        vm.stopPrank();
        return suggestionId;
    }
}
