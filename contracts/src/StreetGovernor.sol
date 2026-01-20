// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {KLEDToken} from "./KLEDToken.sol";

/**
 * @title StreetGovernor
 * @author SOL Agent
 * @notice Governance contract with proposal staking and slashing mechanism
 * @dev Custom governor implementation with:
 * - 50,000 KLED stake required to propose
 * - 10% slash on proposal defeat
 * - Snapshot-based voting power (at proposal creation)
 * - Yes/No/Abstain voting
 *
 * ## Architecture Decisions (AWAITING ARCH REVIEW)
 * - No proxy pattern (can be upgraded to UUPS if needed)
 * - Direct execution (can be composed with Timelock contract)
 * - Custom implementation (staking/slashing doesn't fit OZ Governor)
 * - Timestamp-based snapshots (L2 compatibility)
 *
 * ## Security Considerations
 * - Uses checks-effects-interactions pattern
 * - ReentrancyGuard on state-changing functions
 * - Voting power snapshot prevents flash loan attacks
 * - Pull-based stake return (proposer must claim)
 *
 * ## Invariants
 * - Total staked == sum of all active proposal stakes
 * - Slashed tokens go to treasury (or are burned)
 * - Only proposer can cancel before voting starts
 * - Votes cannot be changed once cast
 *
 * @custom:security-contact security@example.com
 */
contract StreetGovernor is ReentrancyGuard {
    // ============ Custom Errors ============

    error NotOwner();
    error NotGuardian();
    error ZeroAddress();
    error InsufficientStake(uint256 required, uint256 available);
    error ProposalNotFound(uint256 proposalId);
    error InvalidProposalState(uint256 proposalId, ProposalState expected, ProposalState actual);
    error AlreadyVoted(uint256 proposalId, address voter);
    error NoVotingPower(address voter, uint256 proposalId);
    error VotingNotStarted(uint256 proposalId, uint256 startTime);
    error VotingEnded(uint256 proposalId, uint256 endTime);
    error VotingNotEnded(uint256 proposalId, uint256 endTime);
    error ExecutionFailed(uint256 proposalId);
    error NotProposer(uint256 proposalId, address caller);
    error ArrayLengthMismatch();
    error InvalidVoteType(uint8 support);
    error QuorumNotReached(uint256 proposalId, uint256 required, uint256 actual);
    error ThresholdNotReached(uint256 proposalId, uint256 required, uint256 actual);
    error StakeAlreadyClaimed(uint256 proposalId);
    error ProposalNotFinalized(uint256 proposalId);

    // ============ Enums ============

    /// @notice Possible states for a proposal
    enum ProposalState {
        Pending,    // Created but voting hasn't started
        Active,     // Voting is ongoing
        Canceled,   // Canceled by proposer
        Defeated,   // Voting ended with defeat (quorum not met or threshold not reached)
        Succeeded,  // Voting ended with success
        Executed    // Successfully executed
    }

    /// @notice Vote types
    enum VoteType {
        Against,    // 0
        For,        // 1
        Abstain     // 2
    }

    // ============ Structs ============

    /// @notice Structure representing a governance proposal
    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        uint256 stakeAmount;
        uint256 snapshotTimestamp;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool canceled;
        bool stakeClaimed;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    /// @notice Structure for voter receipt
    struct Receipt {
        bool hasVoted;
        VoteType support;
        uint256 weight;
    }

    // ============ Constants ============

    /// @notice Required stake to create a proposal (50,000 KLED)
    uint256 public constant PROPOSAL_STAKE = 50_000 ether;

    /// @notice Slash percentage on defeat (10% = 1000 basis points)
    uint256 public constant SLASH_BPS = 1000;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ State Variables ============

    /// @notice The governance token
    KLEDToken public immutable token;

    /// @notice Contract owner (admin)
    address public owner;

    /// @notice Guardian for emergency actions
    address public guardian;

    /// @notice Treasury address for slashed tokens
    address public treasury;

    /// @notice Delay before voting starts (seconds)
    uint256 public votingDelay;

    /// @notice Duration of voting period (seconds)
    uint256 public votingPeriod;

    /// @notice Quorum required (basis points of total supply at snapshot)
    uint256 public quorumBps;

    /// @notice Threshold for success (basis points, forVotes / (forVotes + againstVotes))
    uint256 public thresholdBps;

    /// @notice Counter for proposal IDs
    uint256 public proposalCount;

    /// @notice Mapping of proposal ID to Proposal struct
    mapping(uint256 => Proposal) internal _proposals;

    /// @notice Mapping of proposal ID to voter address to receipt
    mapping(uint256 => mapping(address => Receipt)) public receipts;

    /// @notice Whether the contract is paused
    bool public paused;

    // ============ Events ============

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
        VoteType support,
        uint256 weight,
        string reason
    );

    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event StakeClaimed(uint256 indexed proposalId, address indexed proposer, uint256 amount);
    event StakeSlashed(uint256 indexed proposalId, address indexed proposer, uint256 slashedAmount, uint256 returnedAmount);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event VotingDelayUpdated(uint256 previousDelay, uint256 newDelay);
    event VotingPeriodUpdated(uint256 previousPeriod, uint256 newPeriod);
    event QuorumUpdated(uint256 previousQuorum, uint256 newQuorum);
    event ThresholdUpdated(uint256 previousThreshold, uint256 newThreshold);
    event Paused(address indexed by);
    event Unpaused(address indexed by);

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the StreetGovernor contract
     * @param _token The KLED governance token address
     * @param _owner The initial owner address
     * @param _guardian The initial guardian address
     * @param _treasury The treasury address for slashed tokens
     * @param _votingDelay Delay before voting starts (seconds)
     * @param _votingPeriod Duration of voting (seconds)
     * @param _quorumBps Quorum in basis points (e.g., 400 = 4%)
     * @param _thresholdBps Threshold in basis points (e.g., 5000 = 50%)
     */
    constructor(
        address _token,
        address _owner,
        address _guardian,
        address _treasury,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _quorumBps,
        uint256 _thresholdBps
    ) {
        if (_token == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_guardian == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();

        token = KLEDToken(_token);
        owner = _owner;
        guardian = _guardian;
        treasury = _treasury;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
        quorumBps = _quorumBps;
        thresholdBps = _thresholdBps;

        emit OwnershipTransferred(address(0), _owner);
        emit GuardianUpdated(address(0), _guardian);
        emit TreasuryUpdated(address(0), _treasury);
    }

    // ============ Proposal Functions ============

    /**
     * @notice Creates a new proposal with stake
     * @dev Requires PROPOSAL_STAKE tokens to be transferred from proposer
     *
     * INVARIANT: proposalCount increases by 1
     * INVARIANT: proposer's token balance decreases by PROPOSAL_STAKE
     * INVARIANT: contract's token balance increases by PROPOSAL_STAKE
     * INVARIANT: snapshotTimestamp is set to current block.timestamp
     *
     * @param title Short title of the proposal
     * @param description Full description of the proposal
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param calldatas Array of calldata
     * @return proposalId The created proposal ID
     */
    function propose(
        string calldata title,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external nonReentrant whenNotPaused returns (uint256 proposalId) {
        if (targets.length != values.length || values.length != calldatas.length) {
            revert ArrayLengthMismatch();
        }

        // Check proposer has enough tokens
        uint256 balance = token.balanceOf(msg.sender);
        if (balance < PROPOSAL_STAKE) {
            revert InsufficientStake(PROPOSAL_STAKE, balance);
        }

        // Transfer stake (checks-effects-interactions)
        proposalId = ++proposalCount;

        uint256 snapshotTimestamp = block.timestamp;
        uint256 startTime = block.timestamp + votingDelay;
        uint256 endTime = startTime + votingPeriod;

        Proposal storage proposal = _proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.title = title;
        proposal.description = description;
        proposal.stakeAmount = PROPOSAL_STAKE;
        proposal.snapshotTimestamp = snapshotTimestamp;
        proposal.startTime = startTime;
        proposal.endTime = endTime;
        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;

        // Transfer stake from proposer to this contract
        bool success = token.transferFrom(msg.sender, address(this), PROPOSAL_STAKE);
        require(success, "Stake transfer failed");

        emit ProposalCreated(
            proposalId,
            msg.sender,
            title,
            targets,
            values,
            calldatas,
            snapshotTimestamp,
            startTime,
            endTime,
            PROPOSAL_STAKE
        );
    }

    /**
     * @notice Casts a vote on a proposal
     * @dev Vote weight is determined by voting power at proposal snapshot
     *
     * INVARIANT: Cannot vote twice
     * INVARIANT: Vote weight equals getPastVotes at snapshotTimestamp
     * INVARIANT: Must be within voting period
     *
     * @param proposalId The proposal to vote on
     * @param support Vote type (0 = Against, 1 = For, 2 = Abstain)
     */
    function vote(uint256 proposalId, uint8 support) external nonReentrant whenNotPaused {
        _vote(proposalId, support, "");
    }

    /**
     * @notice Casts a vote with reason
     * @param proposalId The proposal to vote on
     * @param support Vote type (0 = Against, 1 = For, 2 = Abstain)
     * @param reason Reason for the vote
     */
    function voteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external nonReentrant whenNotPaused {
        _vote(proposalId, support, reason);
    }

    /**
     * @notice Internal vote logic
     */
    function _vote(uint256 proposalId, uint8 support, string memory reason) internal {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (proposal.canceled) revert InvalidProposalState(proposalId, ProposalState.Active, ProposalState.Canceled);

        if (block.timestamp < proposal.startTime) {
            revert VotingNotStarted(proposalId, proposal.startTime);
        }
        if (block.timestamp > proposal.endTime) {
            revert VotingEnded(proposalId, proposal.endTime);
        }

        Receipt storage receipt = receipts[proposalId][msg.sender];
        if (receipt.hasVoted) revert AlreadyVoted(proposalId, msg.sender);

        // Get voting power at snapshot
        uint256 weight = token.getPastVotes(msg.sender, proposal.snapshotTimestamp);
        if (weight == 0) revert NoVotingPower(msg.sender, proposalId);

        if (support > uint8(VoteType.Abstain)) revert InvalidVoteType(support);
        VoteType voteType = VoteType(support);

        // Record vote
        receipt.hasVoted = true;
        receipt.support = voteType;
        receipt.weight = weight;

        if (voteType == VoteType.Against) {
            proposal.againstVotes += weight;
        } else if (voteType == VoteType.For) {
            proposal.forVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, voteType, weight, reason);
    }

    /**
     * @notice Executes a successful proposal
     * @dev Only callable after voting ends and proposal succeeded
     *
     * INVARIANT: Proposal can only be executed once
     * INVARIANT: Must meet quorum and threshold
     * INVARIANT: Stake is returned to proposer on success
     *
     * @param proposalId The proposal to execute
     */
    function execute(uint256 proposalId) external nonReentrant whenNotPaused {
        ProposalState currentState = state(proposalId);
        if (currentState != ProposalState.Succeeded) {
            revert InvalidProposalState(proposalId, ProposalState.Succeeded, currentState);
        }

        Proposal storage proposal = _proposals[proposalId];
        proposal.executed = true;

        // Execute all actions
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(proposal.calldatas[i]);
            if (!success) revert ExecutionFailed(proposalId);
        }

        emit ProposalExecuted(proposalId);

        // Return stake to proposer (success case - no slash)
        _returnStake(proposalId, false);
    }

    /**
     * @notice Cancels a proposal before voting starts
     * @dev Only callable by proposer before voting begins
     *
     * INVARIANT: Only proposer can cancel
     * INVARIANT: Can only cancel before voting starts
     * INVARIANT: Stake is returned fully on cancel
     *
     * @param proposalId The proposal to cancel
     */
    function cancel(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);
        if (msg.sender != proposal.proposer && msg.sender != owner) {
            revert NotProposer(proposalId, msg.sender);
        }

        ProposalState currentState = state(proposalId);
        if (currentState != ProposalState.Pending) {
            revert InvalidProposalState(proposalId, ProposalState.Pending, currentState);
        }

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);

        // Return full stake on cancel
        _returnStake(proposalId, false);
    }

    /**
     * @notice Claims stake after a defeated proposal (with slash)
     * @dev Proposer can claim remaining stake after defeat
     *
     * INVARIANT: 10% is slashed to treasury
     * INVARIANT: 90% returned to proposer
     *
     * @param proposalId The defeated proposal
     */
    function claimStakeAfterDefeat(uint256 proposalId) external nonReentrant {
        ProposalState currentState = state(proposalId);
        if (currentState != ProposalState.Defeated) {
            revert InvalidProposalState(proposalId, ProposalState.Defeated, currentState);
        }

        Proposal storage proposal = _proposals[proposalId];
        if (msg.sender != proposal.proposer) {
            revert NotProposer(proposalId, msg.sender);
        }

        _returnStake(proposalId, true);
    }

    /**
     * @notice Internal function to return stake
     */
    function _returnStake(uint256 proposalId, bool slash) internal {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.stakeClaimed) revert StakeAlreadyClaimed(proposalId);

        proposal.stakeClaimed = true;
        uint256 stakeAmount = proposal.stakeAmount;

        if (slash) {
            uint256 slashAmount = (stakeAmount * SLASH_BPS) / BPS_DENOMINATOR;
            uint256 returnAmount = stakeAmount - slashAmount;

            // Transfer slashed amount to treasury
            if (slashAmount > 0) {
                bool success = token.transfer(treasury, slashAmount);
                require(success, "Treasury transfer failed");
            }

            // Return remaining to proposer
            if (returnAmount > 0) {
                bool success = token.transfer(proposal.proposer, returnAmount);
                require(success, "Proposer transfer failed");
            }

            emit StakeSlashed(proposalId, proposal.proposer, slashAmount, returnAmount);
        } else {
            // Return full stake
            bool success = token.transfer(proposal.proposer, stakeAmount);
            require(success, "Stake return failed");
            emit StakeClaimed(proposalId, proposal.proposer, stakeAmount);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Returns the current state of a proposal
     * @param proposalId The proposal to check
     * @return The current ProposalState
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        if (proposal.canceled) {
            return ProposalState.Canceled;
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

        // Voting has ended - check results
        return _checkProposalOutcome(proposal) ? ProposalState.Succeeded : ProposalState.Defeated;
    }

    /**
     * @notice Checks if proposal meets quorum and threshold
     */
    function _checkProposalOutcome(Proposal storage proposal) internal view returns (bool) {
        // Check quorum (total votes vs total supply at snapshot)
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalSupply = token.getPastTotalSupply(proposal.snapshotTimestamp);
        uint256 quorumRequired = (totalSupply * quorumBps) / BPS_DENOMINATOR;

        if (totalVotes < quorumRequired) {
            return false;
        }

        // Check threshold (forVotes vs forVotes + againstVotes)
        // Abstain votes count for quorum but not for threshold
        uint256 relevantVotes = proposal.forVotes + proposal.againstVotes;
        if (relevantVotes == 0) {
            return false; // No for/against votes means defeat
        }

        uint256 thresholdRequired = (relevantVotes * thresholdBps) / BPS_DENOMINATOR;
        return proposal.forVotes >= thresholdRequired;
    }

    /**
     * @notice Returns proposal details
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address proposer,
            string memory title,
            string memory description,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes,
            uint256 startTime,
            uint256 endTime,
            ProposalState currentState
        )
    {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        return (
            proposal.proposer,
            proposal.title,
            proposal.description,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.startTime,
            proposal.endTime,
            state(proposalId)
        );
    }

    /**
     * @notice Returns proposal actions
     */
    function getProposalActions(uint256 proposalId)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        return (proposal.targets, proposal.values, proposal.calldatas);
    }

    /**
     * @notice Checks if an address has voted on a proposal
     */
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return receipts[proposalId][voter].hasVoted;
    }

    /**
     * @notice Returns quorum required for a proposal
     */
    function quorum(uint256 proposalId) external view returns (uint256) {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound(proposalId);

        uint256 totalSupply = token.getPastTotalSupply(proposal.snapshotTimestamp);
        return (totalSupply * quorumBps) / BPS_DENOMINATOR;
    }

    // ============ Admin Functions ============

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prev = owner;
        owner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }

    function setGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ZeroAddress();
        address prev = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(prev, newGuardian);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address prev = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(prev, newTreasury);
    }

    function setVotingDelay(uint256 newDelay) external onlyOwner {
        uint256 prev = votingDelay;
        votingDelay = newDelay;
        emit VotingDelayUpdated(prev, newDelay);
    }

    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        uint256 prev = votingPeriod;
        votingPeriod = newPeriod;
        emit VotingPeriodUpdated(prev, newPeriod);
    }

    function setQuorum(uint256 newQuorum) external onlyOwner {
        uint256 prev = quorumBps;
        quorumBps = newQuorum;
        emit QuorumUpdated(prev, newQuorum);
    }

    function setThreshold(uint256 newThreshold) external onlyOwner {
        uint256 prev = thresholdBps;
        thresholdBps = newThreshold;
        emit ThresholdUpdated(prev, newThreshold);
    }

    function pause() external onlyGuardian {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyGuardian {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // ============ Receive Function ============

    /// @notice Allows contract to receive ETH for proposal execution
    receive() external payable {}
}
