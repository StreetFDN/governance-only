// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Governance
 * @author SOL Agent
 * @notice A placeholder governance contract for managing proposals and voting
 * @dev This contract implements basic governance functionality with role-based access control
 *
 * ## Architecture Overview
 * - Uses a simple role-based access control with owner, guardian, and proposer roles
 * - Implements pausable pattern from OpenZeppelin for emergency stops
 * - Proposals go through: Created -> Active -> Succeeded/Defeated -> Executed
 *
 * ## Security Considerations
 * - Only authorized proposers can create proposals
 * - Guardian can pause the contract in emergencies
 * - Owner has full administrative control
 *
 * @custom:security-contact security@example.com
 */
contract Governance is Pausable {
    // ============ Custom Errors ============

    /// @notice Thrown when caller is not the owner
    error NotOwner();

    /// @notice Thrown when caller is not a guardian
    error NotGuardian();

    /// @notice Thrown when caller is not a proposer
    error NotProposer();

    /// @notice Thrown when proposal does not exist
    error ProposalNotFound(uint256 proposalId);

    /// @notice Thrown when proposal is not in the expected state
    error InvalidProposalState(uint256 proposalId, ProposalState expected, ProposalState actual);

    /// @notice Thrown when voting period has ended
    error VotingEnded(uint256 proposalId);

    /// @notice Thrown when voting period has not ended
    error VotingNotEnded(uint256 proposalId);

    /// @notice Thrown when user has already voted
    error AlreadyVoted(uint256 proposalId, address voter);

    /// @notice Thrown when execution fails
    error ExecutionFailed(uint256 proposalId);

    /// @notice Thrown when address is zero
    error ZeroAddress();

    // ============ Enums ============

    /// @notice Possible states for a proposal
    enum ProposalState {
        Pending,    // Created but voting hasn't started
        Active,     // Voting is ongoing
        Succeeded,  // Voting ended with success
        Defeated,   // Voting ended with defeat
        Executed,   // Proposal was executed
        Cancelled   // Proposal was cancelled
    }

    // ============ Structs ============

    /// @notice Structure representing a governance proposal
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool cancelled;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    // ============ State Variables ============

    /// @notice Contract owner with full administrative control
    address public owner;

    /// @notice Guardian address that can pause the contract
    address public guardian;

    /// @notice Mapping of addresses that can create proposals
    mapping(address => bool) public isProposer;

    /// @notice Counter for proposal IDs
    uint256 public proposalCount;

    /// @notice Mapping of proposal ID to Proposal struct
    mapping(uint256 => Proposal) public proposals;

    /// @notice Mapping of proposal ID to voter address to whether they voted
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    /// @notice Duration of voting period in seconds
    uint256 public votingPeriod;

    /// @notice Delay before voting starts after proposal creation
    uint256 public votingDelay;

    // ============ Events ============

    /// @notice Emitted when a new proposal is created
    /// @param proposalId The unique identifier for the proposal
    /// @param proposer The address that created the proposal
    /// @param description Human-readable description of the proposal
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

    /// @notice Emitted when a vote is cast
    /// @param proposalId The proposal being voted on
    /// @param voter The address casting the vote
    /// @param support Whether the vote is in favor
    /// @param weight The voting weight (for future token-weighted voting)
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );

    /// @notice Emitted when a proposal is executed
    /// @param proposalId The proposal that was executed
    event ProposalExecuted(uint256 indexed proposalId);

    /// @notice Emitted when a proposal is cancelled
    /// @param proposalId The proposal that was cancelled
    event ProposalCancelled(uint256 indexed proposalId);

    /// @notice Emitted when the owner is changed
    /// @param previousOwner The previous owner address
    /// @param newOwner The new owner address
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when the guardian is changed
    /// @param previousGuardian The previous guardian address
    /// @param newGuardian The new guardian address
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);

    /// @notice Emitted when a proposer role is granted or revoked
    /// @param account The account whose proposer status changed
    /// @param isProposer Whether the account is now a proposer
    event ProposerUpdated(address indexed account, bool isProposer);

    // ============ Modifiers ============

    /// @notice Restricts function to owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Restricts function to guardian only
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    /// @notice Restricts function to proposers only
    modifier onlyProposer() {
        if (!isProposer[msg.sender]) revert NotProposer();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the governance contract
     * @param _owner The initial owner address
     * @param _guardian The initial guardian address
     * @param _votingPeriod Duration of voting in seconds
     * @param _votingDelay Delay before voting starts in seconds
     */
    constructor(
        address _owner,
        address _guardian,
        uint256 _votingPeriod,
        uint256 _votingDelay
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_guardian == address(0)) revert ZeroAddress();

        owner = _owner;
        guardian = _guardian;
        votingPeriod = _votingPeriod;
        votingDelay = _votingDelay;

        // Owner is also a proposer by default
        isProposer[_owner] = true;
        emit ProposerUpdated(_owner, true);
    }

    // ============ External Functions ============

    /**
     * @notice Creates a new governance proposal
     * @dev Only callable by addresses with proposer role
     *
     * INVARIANT: proposalCount should always increase by exactly 1
     * INVARIANT: proposal.startTime should always be > block.timestamp
     * INVARIANT: proposal.endTime should always be > proposal.startTime
     *
     * @param targets Array of target addresses for the proposal actions
     * @param values Array of ETH values to send with each action
     * @param calldatas Array of calldata for each action
     * @param description Human-readable description of the proposal
     * @return proposalId The unique identifier of the created proposal
     */
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external onlyProposer whenNotPaused returns (uint256 proposalId) {
        // TODO: Implement proposal creation logic
        // - Validate arrays have same length
        // - Create proposal struct
        // - Store in mapping
        // - Emit event

        proposalId = ++proposalCount;
        uint256 startTime = block.timestamp + votingDelay;
        uint256 endTime = startTime + votingPeriod;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.startTime = startTime;
        proposal.endTime = endTime;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            description,
            targets,
            values,
            calldatas,
            startTime,
            endTime
        );

        return proposalId;
    }

    /**
     * @notice Casts a vote on an active proposal
     * @dev Each address can only vote once per proposal
     *
     * INVARIANT: hasVoted[proposalId][voter] should be true after voting
     * INVARIANT: forVotes + againstVotes should increase by vote weight
     * INVARIANT: Users cannot vote after endTime
     *
     * @param proposalId The proposal to vote on
     * @param support True for voting in favor, false for against
     */
    function vote(uint256 proposalId, bool support) external whenNotPaused {
        // TODO: Implement voting logic
        // - Check proposal exists and is active
        // - Check user hasn't voted
        // - Record vote
        // - Update vote counts
        // - Emit event

        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (block.timestamp < proposal.startTime || block.timestamp > proposal.endTime) {
            revert VotingEnded(proposalId);
        }
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted(proposalId, msg.sender);

        hasVoted[proposalId][msg.sender] = true;

        // TODO: Implement token-weighted voting
        uint256 weight = 1; // Placeholder: equal weight voting

        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Executes a successful proposal
     * @dev Only callable after voting period ends and proposal succeeded
     *
     * INVARIANT: Proposal can only be executed once
     * INVARIANT: Proposal must have more forVotes than againstVotes
     * INVARIANT: All target calls must succeed or entire execution reverts
     *
     * @param proposalId The proposal to execute
     */
    function execute(uint256 proposalId) external whenNotPaused {
        // TODO: Implement execution logic
        // - Check proposal exists
        // - Check voting has ended
        // - Check proposal succeeded
        // - Check not already executed
        // - Execute all actions
        // - Mark as executed
        // - Emit event

        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (block.timestamp <= proposal.endTime) revert VotingNotEnded(proposalId);
        if (proposal.executed) {
            revert InvalidProposalState(
                proposalId,
                ProposalState.Succeeded,
                ProposalState.Executed
            );
        }

        // Check proposal succeeded
        if (proposal.forVotes <= proposal.againstVotes) {
            revert InvalidProposalState(
                proposalId,
                ProposalState.Succeeded,
                ProposalState.Defeated
            );
        }

        proposal.executed = true;

        // Execute all actions
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            if (!success) revert ExecutionFailed(proposalId);
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Pauses the contract, preventing proposals, voting, and execution
     * @dev Only callable by guardian
     *
     * INVARIANT: Only guardian can pause
     * INVARIANT: Contract state should be paused after call
     */
    function pause() external onlyGuardian {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by guardian
     *
     * INVARIANT: Only guardian can unpause
     * INVARIANT: Contract state should be unpaused after call
     */
    function unpause() external onlyGuardian {
        _unpause();
    }

    // ============ Admin Functions ============

    /**
     * @notice Transfers ownership to a new address
     * @param newOwner The address to transfer ownership to
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @notice Updates the guardian address
     * @param newGuardian The new guardian address
     */
    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        address previousGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(previousGuardian, newGuardian);
    }

    /**
     * @notice Grants or revokes proposer role
     * @param account The account to update
     * @param _isProposer Whether to grant or revoke proposer role
     */
    function setProposer(address account, bool _isProposer) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        isProposer[account] = _isProposer;
        emit ProposerUpdated(account, _isProposer);
    }

    /**
     * @notice Cancels a proposal
     * @dev Only callable by owner or the proposal's proposer
     * @param proposalId The proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        // Only owner or proposer can cancel
        if (msg.sender != owner && msg.sender != proposal.proposer) {
            revert NotOwner();
        }

        proposal.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    // ============ View Functions ============

    /**
     * @notice Returns the current state of a proposal
     * @param proposalId The proposal to check
     * @return The current ProposalState
     */
    function state(uint256 proposalId) external view returns (ProposalState) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        if (proposal.cancelled) {
            return ProposalState.Cancelled;
        }
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        if (block.timestamp < proposal.startTime) {
            return ProposalState.Pending;
        }
        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Active;
        }
        if (proposal.forVotes > proposal.againstVotes) {
            return ProposalState.Succeeded;
        }
        return ProposalState.Defeated;
    }

    /**
     * @notice Returns proposal details
     * @param proposalId The proposal to query
     * @return proposer The address that created the proposal
     * @return forVotes Number of votes in favor
     * @return againstVotes Number of votes against
     * @return startTime When voting starts
     * @return endTime When voting ends
     * @return executed Whether the proposal was executed
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address proposer,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 startTime,
            uint256 endTime,
            bool executed
        )
    {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        return (
            proposal.proposer,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.startTime,
            proposal.endTime,
            proposal.executed
        );
    }

    /**
     * @notice Checks if a proposal has been voted on by an address
     * @param proposalId The proposal to check
     * @param voter The address to check
     * @return Whether the address has voted on the proposal
     */
    function hasVotedOnProposal(uint256 proposalId, address voter) external view returns (bool) {
        return hasVoted[proposalId][voter];
    }

    // ============ Receive Function ============

    /// @notice Allows contract to receive ETH for proposal execution
    receive() external payable {}
}
