// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

/**
 * @title BaseTest
 * @notice Base test contract with shared setup for Street Governance tests
 * @dev Provides common actors, constants, and helper functions
 *
 * ## Architecture
 * KLEDToken (ERC20Votes) -> StreetGovernor -> Timelock
 *                       -> EditSuggestions
 *
 * ## Test Requirements (from status.md)
 * - Proposal creation requires 50,000 KLED stake
 * - Voting (Yes/No/Abstain) weighted by token balance at snapshot
 * - 10% slashing on failed proposals
 * - Edit suggestions require 500 KLED stake
 * - Snapshot voting prevents flash loan attacks
 */
abstract contract BaseTest is Test {
    // ============ Constants ============

    uint256 public constant PROPOSAL_STAKE = 50_000e18; // 50K KLED
    uint256 public constant EDIT_STAKE = 500e18; // 500 KLED
    uint256 public constant SLASH_PERCENTAGE = 10; // 10%

    uint256 public constant VOTING_DELAY = 1; // 1 block
    uint256 public constant VOTING_PERIOD = 100; // 100 blocks
    uint256 public constant EDIT_WINDOW = 48 hours;
    uint256 public constant EDIT_VOTING_WINDOW = 72 hours;
    uint256 public constant TIMELOCK_DELAY = 10; // 10 blocks

    uint256 public constant INITIAL_SUPPLY = 100_000_000e18; // 100M KLED

    // ============ Test Actors ============

    address public deployer;
    address public alice; // Standard voter: 10K KLED
    address public bob; // Standard voter: 25K KLED
    address public proposer; // Meets threshold: 100K KLED
    address public whale; // Large holder: 1M KLED
    address public attacker; // Malicious actor
    address public treasury; // Protocol treasury

    // Actor balances (set in _fundActors)
    uint256 public constant ALICE_BALANCE = 10_000e18;
    uint256 public constant BOB_BALANCE = 25_000e18;
    uint256 public constant PROPOSER_BALANCE = 100_000e18;
    uint256 public constant WHALE_BALANCE = 1_000_000e18;

    // ============ Setup ============

    function setUp() public virtual {
        _createActors();
        _deployContracts();
        _fundActors();
        _setupDelegations();
    }

    function _createActors() internal {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        proposer = makeAddr("proposer");
        whale = makeAddr("whale");
        attacker = makeAddr("attacker");
        treasury = makeAddr("treasury");
    }

    /// @dev Override in child tests to deploy actual contracts
    function _deployContracts() internal virtual;

    /// @dev Override in child tests to fund actors with tokens
    function _fundActors() internal virtual;

    /// @dev Override in child tests to setup delegations
    function _setupDelegations() internal virtual;

    // ============ Helper Functions ============

    /// @notice Calculates 10% slash amount
    function _calculateSlash(uint256 stake) internal pure returns (uint256) {
        return (stake * SLASH_PERCENTAGE) / 100;
    }

    /// @notice Advances block number
    function _advanceBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }

    /// @notice Advances time
    function _advanceTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /// @notice Advances both block and time proportionally
    function _advanceBlocksAndTime(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + (blocks * 12)); // ~12 sec per block on L2
    }

    /// @notice Labels addresses for better trace output
    function _labelAddresses() internal {
        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(proposer, "Proposer");
        vm.label(whale, "Whale");
        vm.label(attacker, "Attacker");
        vm.label(treasury, "Treasury");
    }
}
