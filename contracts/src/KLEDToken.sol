// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title KLEDToken
 * @author SOL Agent
 * @notice ERC20 governance token with delegation support for the Street Governance system
 * @dev Implements ERC20Votes for snapshot-based voting power and delegation
 *
 * ## Features
 * - ERC20 standard functionality
 * - ERC20Votes for voting power delegation and historical checkpoints
 * - ERC20Permit for gasless approvals via EIP-2612
 * - Owner-controlled minting with ability to permanently lock
 * - 18 decimals (standard)
 *
 * ## Security Considerations
 * - Minting is restricted to owner
 * - Minting can be permanently locked (irreversible)
 * - Uses OpenZeppelin battle-tested implementations
 * - Voting power is snapshotted at proposal creation time (handled by Governor)
 *
 * ## Invariants
 * - totalSupply == sum of all balances
 * - For each account: getVotes(account) == delegated voting power at current block
 * - Once mintingLocked == true, no more tokens can ever be minted
 * - owner can only be changed by current owner
 *
 * @custom:security-contact security@example.com
 */
contract KLEDToken is ERC20, ERC20Permit, ERC20Votes {
    // ============ Custom Errors ============

    /// @notice Thrown when caller is not the owner
    error NotOwner();

    /// @notice Thrown when minting is attempted after it's been locked
    error MintingLocked();

    /// @notice Thrown when trying to mint zero tokens
    error ZeroMintAmount();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    // ============ State Variables ============

    /// @notice Contract owner with minting privileges
    address public owner;

    /// @notice Whether minting has been permanently locked
    bool public mintingLocked;

    // ============ Events ============

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner The previous owner address
    /// @param newOwner The new owner address
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when minting is permanently locked
    /// @param locker The address that locked minting
    /// @param totalSupplyAtLock The total supply when minting was locked
    event MintingPermanentlyLocked(address indexed locker, uint256 totalSupplyAtLock);

    /// @notice Emitted when tokens are minted
    /// @param to The recipient of the minted tokens
    /// @param amount The amount minted
    event TokensMinted(address indexed to, uint256 amount);

    // ============ Modifiers ============

    /// @notice Restricts function to owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initializes the KLED token
     * @param _owner The initial owner address with minting privileges
     * @param _initialSupply Initial token supply to mint to owner (can be 0)
     */
    constructor(
        address _owner,
        uint256 _initialSupply
    ) ERC20("KLED Token", "KLED") ERC20Permit("KLED Token") {
        if (_owner == address(0)) revert ZeroAddress();

        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);

        if (_initialSupply > 0) {
            _mint(_owner, _initialSupply);
            emit TokensMinted(_owner, _initialSupply);
        }
    }

    // ============ External Functions ============

    /**
     * @notice Mints new tokens to a specified address
     * @dev Only callable by owner when minting is not locked
     *
     * INVARIANT: totalSupply increases by exactly `amount`
     * INVARIANT: recipient balance increases by exactly `amount`
     * INVARIANT: Cannot mint when mintingLocked == true
     *
     * @param to The recipient of the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (mintingLocked) revert MintingLocked();
        if (amount == 0) revert ZeroMintAmount();
        if (to == address(0)) revert ZeroAddress();

        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @notice Permanently locks minting capability
     * @dev This action is IRREVERSIBLE. Once locked, no more tokens can ever be minted.
     *
     * INVARIANT: After calling, mintingLocked == true forever
     * INVARIANT: totalSupply can never increase after this call
     *
     * Use this to transition from "mintable by owner" to "fixed supply"
     */
    function lockMinting() external onlyOwner {
        if (mintingLocked) revert MintingLocked();

        mintingLocked = true;
        emit MintingPermanentlyLocked(msg.sender, totalSupply());
    }

    /**
     * @notice Transfers ownership to a new address
     * @dev Only callable by current owner
     * @param newOwner The address to transfer ownership to
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    // ============ ERC20Votes Overrides ============

    /**
     * @notice Returns the current timestamp as the clock value
     * @dev Using block.timestamp for L2 compatibility (block.number is unreliable on L2s)
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Returns the clock mode description
     * @dev Indicates we're using timestamp-based voting
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // ============ Required Overrides ============

    /**
     * @dev Override required by Solidity for multiple inheritance
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Override required by Solidity for ERC20Permit and ERC20Votes
     */
    function nonces(address account) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(account);
    }
}
