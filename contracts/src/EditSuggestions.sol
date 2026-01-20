// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {KLEDToken} from "./KLEDToken.sol";
import {StreetGovernor} from "./StreetGovernor.sol";

/**
 * @title EditSuggestions
 * @author SOL Agent
 * @notice Allows KLED holders to suggest edits to governance proposals
 * @dev Implements a staking mechanism for edit suggestions with voting
 *
 * ## Features
 * - 500 KLED stake required per edit suggestion
 * - 48h window to propose edits after proposal creation
 * - 72h window to vote on suggestions after edit window ends
 * - Token-weighted voting on suggestions
 * - Stake returned on accepted suggestions, slashed on rejected
 *
 * ## Security Considerations
 * - Uses ReentrancyGuard for state-changing functions
 * - Integrates with StreetGovernor for proposal validation
 * - Time-bound windows prevent manipulation
 *
 * ## Invariants
 * - Total staked in active suggestions <= contract token balance
 * - Cannot suggest edits outside edit window
 * - Cannot vote on suggestions outside voting window
 * - Each address can only vote once per suggestion
 *
 * @custom:security-contact security@example.com
 */
contract EditSuggestions is ReentrancyGuard {
    // ============ Custom Errors ============

    error NotOwner();
    error ZeroAddress();
    error ProposalNotFound(uint256 proposalId);
    error SuggestionNotFound(uint256 suggestionId);
    error EditWindowClosed(uint256 proposalId, uint256 deadline);
    error EditWindowNotEnded(uint256 proposalId, uint256 deadline);
    error VotingWindowClosed(uint256 suggestionId, uint256 deadline);
    error VotingWindowNotStarted(uint256 suggestionId, uint256 startTime);
    error InsufficientStake(uint256 required, uint256 available);
    error AlreadyVoted(uint256 suggestionId, address voter);
    error NoVotingPower(address voter, uint256 proposalId);
    error SuggestionNotFinalized(uint256 suggestionId);
    error SuggestionAlreadyFinalized(uint256 suggestionId);
    error StakeAlreadyClaimed(uint256 suggestionId);
    error InvalidProposalState();

    // ============ Structs ============

    /// @notice Structure representing an edit suggestion
    struct Suggestion {
        uint256 id;
        uint256 proposalId;
        address suggester;
        bytes32 originalHash;
        string proposedText;
        uint256 stakeAmount;
        uint256 snapshotTimestamp;
        uint256 editDeadline;
        uint256 voteDeadline;
        uint256 forVotes;
        uint256 againstVotes;
        bool finalized;
        bool accepted;
        bool stakeClaimed;
    }

    /// @notice Structure for voter receipt
    struct VoteReceipt {
        bool hasVoted;
        bool support;
        uint256 weight;
    }

    // ============ Constants ============

    /// @notice Required stake for edit suggestion (500 KLED)
    uint256 public constant EDIT_STAKE = 500 ether;

    /// @notice Duration of edit proposal window
    uint256 public constant EDIT_WINDOW = 48 hours;

    /// @notice Duration of suggestion voting window
    uint256 public constant VOTING_WINDOW = 72 hours;

    /// @notice Slash percentage on rejected suggestion (10%)
    uint256 public constant SLASH_BPS = 1000;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ State Variables ============

    /// @notice The governance token
    KLEDToken public immutable token;

    /// @notice The governor contract
    StreetGovernor public immutable governor;

    /// @notice Contract owner
    address public owner;

    /// @notice Treasury for slashed stakes
    address public treasury;

    /// @notice Counter for suggestion IDs
    uint256 public suggestionCount;

    /// @notice Mapping of suggestion ID to Suggestion struct
    mapping(uint256 => Suggestion) internal _suggestions;

    /// @notice Mapping of proposal ID to array of suggestion IDs
    mapping(uint256 => uint256[]) public proposalSuggestions;

    /// @notice Mapping of suggestion ID to voter address to receipt
    mapping(uint256 => mapping(address => VoteReceipt)) public voteReceipts;

    /// @notice Mapping of proposal ID to edit window deadline
    mapping(uint256 => uint256) public editDeadlines;

    // ============ Events ============

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

    event SuggestionStakeClaimed(
        uint256 indexed suggestionId,
        address indexed suggester,
        uint256 amount,
        bool slashed
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the EditSuggestions contract
     * @param _token The KLED governance token address
     * @param _governor The StreetGovernor contract address
     * @param _owner The initial owner address
     * @param _treasury The treasury address for slashed stakes
     */
    constructor(
        address _token,
        address _governor,
        address _owner,
        address _treasury
    ) {
        if (_token == address(0)) revert ZeroAddress();
        if (_governor == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();

        token = KLEDToken(_token);
        governor = StreetGovernor(payable(_governor));
        owner = _owner;
        treasury = _treasury;

        emit OwnershipTransferred(address(0), _owner);
        emit TreasuryUpdated(address(0), _treasury);
    }

    // ============ External Functions ============

    /**
     * @notice Proposes an edit to a governance proposal
     * @dev Requires EDIT_STAKE tokens and must be within edit window
     *
     * INVARIANT: suggestionCount increases by 1
     * INVARIANT: suggester's token balance decreases by EDIT_STAKE
     * INVARIANT: Can only propose during edit window
     *
     * @param proposalId The proposal to suggest an edit for
     * @param originalHash Hash of the original text being edited
     * @param proposedText The suggested new text
     * @return suggestionId The created suggestion ID
     */
    function proposeEdit(
        uint256 proposalId,
        bytes32 originalHash,
        string calldata proposedText
    ) external nonReentrant returns (uint256 suggestionId) {
        // Validate proposal exists and is in valid state
        _validateProposal(proposalId);

        // Initialize edit deadline if first suggestion
        if (editDeadlines[proposalId] == 0) {
            editDeadlines[proposalId] = block.timestamp + EDIT_WINDOW;
        }

        // Check we're in edit window
        uint256 deadline = editDeadlines[proposalId];
        if (block.timestamp > deadline) {
            revert EditWindowClosed(proposalId, deadline);
        }

        // Check suggester has enough tokens
        uint256 balance = token.balanceOf(msg.sender);
        if (balance < EDIT_STAKE) {
            revert InsufficientStake(EDIT_STAKE, balance);
        }

        // Create suggestion
        suggestionId = ++suggestionCount;
        uint256 voteDeadline = deadline + VOTING_WINDOW;

        Suggestion storage suggestion = _suggestions[suggestionId];
        suggestion.id = suggestionId;
        suggestion.proposalId = proposalId;
        suggestion.suggester = msg.sender;
        suggestion.originalHash = originalHash;
        suggestion.proposedText = proposedText;
        suggestion.stakeAmount = EDIT_STAKE;
        suggestion.snapshotTimestamp = block.timestamp;
        suggestion.editDeadline = deadline;
        suggestion.voteDeadline = voteDeadline;

        proposalSuggestions[proposalId].push(suggestionId);

        // Transfer stake
        bool success = token.transferFrom(msg.sender, address(this), EDIT_STAKE);
        require(success, "Stake transfer failed");

        emit SuggestionCreated(
            suggestionId,
            proposalId,
            msg.sender,
            originalHash,
            proposedText,
            EDIT_STAKE,
            deadline,
            voteDeadline
        );
    }

    /**
     * @notice Votes on an edit suggestion
     * @dev Uses voting power from proposal's snapshot timestamp
     *
     * INVARIANT: Cannot vote twice on same suggestion
     * INVARIANT: Must be within voting window
     * INVARIANT: Vote weight from snapshot timestamp
     *
     * @param suggestionId The suggestion to vote on
     * @param support True to support the edit, false to reject
     */
    function voteOnSuggestion(uint256 suggestionId, bool support) external nonReentrant {
        Suggestion storage suggestion = _suggestions[suggestionId];
        if (suggestion.id == 0) revert SuggestionNotFound(suggestionId);
        if (suggestion.finalized) revert SuggestionAlreadyFinalized(suggestionId);

        // Check voting window
        if (block.timestamp < suggestion.editDeadline) {
            revert VotingWindowNotStarted(suggestionId, suggestion.editDeadline);
        }
        if (block.timestamp > suggestion.voteDeadline) {
            revert VotingWindowClosed(suggestionId, suggestion.voteDeadline);
        }

        // Check hasn't voted
        VoteReceipt storage receipt = voteReceipts[suggestionId][msg.sender];
        if (receipt.hasVoted) revert AlreadyVoted(suggestionId, msg.sender);

        // Get voting power at suggestion snapshot
        uint256 weight = token.getPastVotes(msg.sender, suggestion.snapshotTimestamp);
        if (weight == 0) revert NoVotingPower(msg.sender, suggestion.proposalId);

        // Record vote
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.weight = weight;

        if (support) {
            suggestion.forVotes += weight;
        } else {
            suggestion.againstVotes += weight;
        }

        emit SuggestionVoteCast(suggestionId, msg.sender, support, weight);
    }

    /**
     * @notice Finalizes a suggestion after voting ends
     * @dev Determines if suggestion is accepted based on votes
     *
     * @param suggestionId The suggestion to finalize
     */
    function finalizeSuggestion(uint256 suggestionId) external nonReentrant {
        Suggestion storage suggestion = _suggestions[suggestionId];
        if (suggestion.id == 0) revert SuggestionNotFound(suggestionId);
        if (suggestion.finalized) revert SuggestionAlreadyFinalized(suggestionId);
        if (block.timestamp <= suggestion.voteDeadline) {
            revert VotingWindowClosed(suggestionId, suggestion.voteDeadline);
        }

        suggestion.finalized = true;
        suggestion.accepted = suggestion.forVotes > suggestion.againstVotes;

        emit SuggestionFinalized(
            suggestionId,
            suggestion.accepted,
            suggestion.forVotes,
            suggestion.againstVotes
        );
    }

    /**
     * @notice Claims stake after suggestion is finalized
     * @dev Returns full stake if accepted, slashes 10% if rejected
     *
     * @param suggestionId The suggestion to claim stake for
     */
    function claimStake(uint256 suggestionId) external nonReentrant {
        Suggestion storage suggestion = _suggestions[suggestionId];
        if (suggestion.id == 0) revert SuggestionNotFound(suggestionId);
        if (!suggestion.finalized) revert SuggestionNotFinalized(suggestionId);
        if (suggestion.stakeClaimed) revert StakeAlreadyClaimed(suggestionId);

        suggestion.stakeClaimed = true;
        uint256 stakeAmount = suggestion.stakeAmount;
        address suggester = suggestion.suggester;

        if (suggestion.accepted) {
            // Return full stake
            bool success = token.transfer(suggester, stakeAmount);
            require(success, "Stake return failed");
            emit SuggestionStakeClaimed(suggestionId, suggester, stakeAmount, false);
        } else {
            // Slash 10%, return 90%
            uint256 slashAmount = (stakeAmount * SLASH_BPS) / BPS_DENOMINATOR;
            uint256 returnAmount = stakeAmount - slashAmount;

            if (slashAmount > 0) {
                bool success = token.transfer(treasury, slashAmount);
                require(success, "Treasury transfer failed");
            }
            if (returnAmount > 0) {
                bool success = token.transfer(suggester, returnAmount);
                require(success, "Suggester transfer failed");
            }

            emit SuggestionStakeClaimed(suggestionId, suggester, returnAmount, true);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns suggestion details
     */
    function getSuggestion(uint256 suggestionId)
        external
        view
        returns (
            uint256 proposalId,
            address suggester,
            bytes32 originalHash,
            string memory proposedText,
            uint256 forVotes,
            uint256 againstVotes,
            bool finalized,
            bool accepted
        )
    {
        Suggestion storage suggestion = _suggestions[suggestionId];
        if (suggestion.id == 0) revert SuggestionNotFound(suggestionId);

        return (
            suggestion.proposalId,
            suggestion.suggester,
            suggestion.originalHash,
            suggestion.proposedText,
            suggestion.forVotes,
            suggestion.againstVotes,
            suggestion.finalized,
            suggestion.accepted
        );
    }

    /**
     * @notice Returns all suggestion IDs for a proposal
     */
    function getSuggestions(uint256 proposalId) external view returns (uint256[] memory) {
        return proposalSuggestions[proposalId];
    }

    /**
     * @notice Checks if address has voted on a suggestion
     */
    function hasVoted(uint256 suggestionId, address voter) external view returns (bool) {
        return voteReceipts[suggestionId][voter].hasVoted;
    }

    /**
     * @notice Returns the edit window deadline for a proposal
     */
    function getEditDeadline(uint256 proposalId) external view returns (uint256) {
        return editDeadlines[proposalId];
    }

    /**
     * @notice Returns the vote deadline for a suggestion
     */
    function getVoteDeadline(uint256 suggestionId) external view returns (uint256) {
        Suggestion storage suggestion = _suggestions[suggestionId];
        if (suggestion.id == 0) revert SuggestionNotFound(suggestionId);
        return suggestion.voteDeadline;
    }

    // ============ Admin Functions ============

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = owner;
        owner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address prev = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(prev, newTreasury);
    }

    // ============ Internal Functions ============

    /**
     * @notice Validates that a proposal exists and is in a valid state for edits
     */
    function _validateProposal(uint256 proposalId) internal view {
        // Check proposal exists by calling governor
        try governor.state(proposalId) returns (StreetGovernor.ProposalState state) {
            // Only allow edits for Pending proposals
            if (state != StreetGovernor.ProposalState.Pending) {
                revert InvalidProposalState();
            }
        } catch {
            revert ProposalNotFound(proposalId);
        }
    }
}
