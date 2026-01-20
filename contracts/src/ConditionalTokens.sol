// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ConditionalTokens
 * @author Street Governance
 * @notice ERC-1155 tokens representing conditional outcomes for Futarchy prediction markets
 * @dev Simplified implementation where only FutarchyTreasury can mint/burn tokens
 *
 * Token ID Scheme:
 * - tokenId = uint256(keccak256(abi.encodePacked(proposalId, isPass)))
 * - Each proposal has exactly 2 tokens: PASS outcome and FAIL outcome
 *
 * Invariants:
 * - CTK-1: Only FutarchyTreasury can mint/burn tokens
 * - CTK-2: totalMinted[tokenId] - totalRedeemed[tokenId] == totalSupply(tokenId)
 * - CTK-3: Token ID is deterministic: keccak256(proposalId, isPass)
 * - CTK-4: PASS and FAIL tokens have different token IDs for same proposal
 */
contract ConditionalTokens is ERC1155, Initializable, UUPSUpgradeable, ReentrancyGuard {
    // =============================================================
    //                           ERRORS
    // =============================================================

    /// @notice Thrown when caller is not the authorized treasury
    error OnlyTreasury();

    /// @notice Thrown when trying to set treasury to zero address
    error ZeroAddress();

    /// @notice Thrown when trying to set treasury after it's already set
    error TreasuryAlreadySet();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when burning more than balance
    error InsufficientBalance();

    // =============================================================
    //                           EVENTS
    // =============================================================

    /// @notice Emitted when outcome tokens are minted
    /// @param proposalId The proposal these tokens belong to
    /// @param to Recipient of the tokens
    /// @param isPass True for PASS outcome, false for FAIL outcome
    /// @param amount Number of tokens minted
    event OutcomeTokensMinted(
        uint256 indexed proposalId,
        address indexed to,
        bool isPass,
        uint256 amount
    );

    /// @notice Emitted when outcome tokens are burned (redeemed)
    /// @param proposalId The proposal these tokens belong to
    /// @param from Address tokens were burned from
    /// @param isPass True for PASS outcome, false for FAIL outcome
    /// @param amount Number of tokens burned
    event OutcomeTokensBurned(
        uint256 indexed proposalId,
        address indexed from,
        bool isPass,
        uint256 amount
    );

    /// @notice Emitted when treasury address is set
    /// @param treasury The treasury contract address
    event TreasurySet(address indexed treasury);

    // =============================================================
    //                           STORAGE
    // =============================================================

    /// @notice Address of the FutarchyTreasury contract (only address that can mint/burn)
    address public treasury;

    /// @notice Total tokens minted for each token ID
    /// @dev tokenId => total minted
    mapping(uint256 => uint256) public totalMinted;

    /// @notice Total tokens redeemed (burned) for each token ID
    /// @dev tokenId => total redeemed
    mapping(uint256 => uint256) public totalRedeemed;

    /// @notice Total supply for each token ID (calculated as minted - redeemed)
    /// @dev tokenId => current supply
    mapping(uint256 => uint256) private _totalSupply;

    /// @notice Storage gap for future upgrades
    uint256[47] private __gap;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /// @notice Constructor disables initializers for implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC1155("") {
        _disableInitializers();
    }

    // =============================================================
    //                         INITIALIZER
    // =============================================================

    /**
     * @notice Initialize the contract
     * @dev Called once during proxy deployment
     * @param uri_ Base URI for token metadata (can be empty)
     */
    function initialize(string memory uri_) external initializer {
        // Note: ERC1155 doesn't have an initializer in OZ 5.x
        // The URI is set in constructor, but we can override it
        // For upgradeable pattern, we leave URI as empty and use tokenURI override if needed
        (uri_); // Silence unused parameter warning - URI handled by ERC1155 constructor
    }

    // =============================================================
    //                      TREASURY MANAGEMENT
    // =============================================================

    /**
     * @notice Set the treasury address (can only be set once)
     * @dev Called after deployment to link to FutarchyTreasury
     * @param treasury_ Address of the FutarchyTreasury contract
     */
    function setTreasury(address treasury_) external {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury != address(0)) revert TreasuryAlreadySet();

        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    // =============================================================
    //                        MODIFIERS
    // =============================================================

    /// @notice Restricts function to treasury only
    modifier onlyTreasury() {
        if (msg.sender != treasury) revert OnlyTreasury();
        _;
    }

    // =============================================================
    //                     TOKEN ID CALCULATION
    // =============================================================

    /**
     * @notice Calculate the token ID for a given proposal and outcome
     * @param proposalId The proposal ID from FutarchyTreasury
     * @param isPass True for PASS outcome token, false for FAIL outcome token
     * @return tokenId The ERC1155 token ID
     */
    function getTokenId(uint256 proposalId, bool isPass) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(proposalId, isPass)));
    }

    /**
     * @notice Get the PASS token ID for a proposal
     * @param proposalId The proposal ID
     * @return tokenId The PASS outcome token ID
     */
    function getPassTokenId(uint256 proposalId) external pure returns (uint256) {
        return getTokenId(proposalId, true);
    }

    /**
     * @notice Get the FAIL token ID for a proposal
     * @param proposalId The proposal ID
     * @return tokenId The FAIL outcome token ID
     */
    function getFailTokenId(uint256 proposalId) external pure returns (uint256) {
        return getTokenId(proposalId, false);
    }

    // =============================================================
    //                     MINT / BURN FUNCTIONS
    // =============================================================

    /**
     * @notice Mint outcome tokens to an address
     * @dev Only callable by FutarchyTreasury when users buy outcome tokens
     * @param to Recipient address
     * @param proposalId The proposal ID
     * @param isPass True for PASS tokens, false for FAIL tokens
     * @param amount Number of tokens to mint
     */
    function mint(
        address to,
        uint256 proposalId,
        bool isPass,
        uint256 amount
    ) external onlyTreasury nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 tokenId = getTokenId(proposalId, isPass);

        // Update accounting
        totalMinted[tokenId] += amount;
        _totalSupply[tokenId] += amount;

        // Mint tokens
        _mint(to, tokenId, amount, "");

        emit OutcomeTokensMinted(proposalId, to, isPass, amount);
    }

    /**
     * @notice Mint outcome tokens in batch
     * @dev Only callable by FutarchyTreasury
     * @param to Recipient address
     * @param proposalIds Array of proposal IDs
     * @param isPassFlags Array of outcome flags
     * @param amounts Array of amounts to mint
     */
    function mintBatch(
        address to,
        uint256[] calldata proposalIds,
        bool[] calldata isPassFlags,
        uint256[] calldata amounts
    ) external onlyTreasury nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 length = proposalIds.length;
        require(length == isPassFlags.length && length == amounts.length, "Length mismatch");

        uint256[] memory tokenIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] == 0) revert ZeroAmount();

            uint256 tokenId = getTokenId(proposalIds[i], isPassFlags[i]);
            tokenIds[i] = tokenId;

            // Update accounting
            totalMinted[tokenId] += amounts[i];
            _totalSupply[tokenId] += amounts[i];

            emit OutcomeTokensMinted(proposalIds[i], to, isPassFlags[i], amounts[i]);
        }

        _mintBatch(to, tokenIds, amounts, "");
    }

    /**
     * @notice Burn outcome tokens from an address
     * @dev Only callable by FutarchyTreasury during redemption
     * @param from Address to burn from
     * @param proposalId The proposal ID
     * @param isPass True for PASS tokens, false for FAIL tokens
     * @param amount Number of tokens to burn
     */
    function burn(
        address from,
        uint256 proposalId,
        bool isPass,
        uint256 amount
    ) external onlyTreasury nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 tokenId = getTokenId(proposalId, isPass);

        if (balanceOf(from, tokenId) < amount) revert InsufficientBalance();

        // Update accounting
        totalRedeemed[tokenId] += amount;
        _totalSupply[tokenId] -= amount;

        // Burn tokens
        _burn(from, tokenId, amount);

        emit OutcomeTokensBurned(proposalId, from, isPass, amount);
    }

    /**
     * @notice Burn outcome tokens in batch
     * @dev Only callable by FutarchyTreasury
     * @param from Address to burn from
     * @param proposalIds Array of proposal IDs
     * @param isPassFlags Array of outcome flags
     * @param amounts Array of amounts to burn
     */
    function burnBatch(
        address from,
        uint256[] calldata proposalIds,
        bool[] calldata isPassFlags,
        uint256[] calldata amounts
    ) external onlyTreasury nonReentrant {
        uint256 length = proposalIds.length;
        require(length == isPassFlags.length && length == amounts.length, "Length mismatch");

        uint256[] memory tokenIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] == 0) revert ZeroAmount();

            uint256 tokenId = getTokenId(proposalIds[i], isPassFlags[i]);
            tokenIds[i] = tokenId;

            if (balanceOf(from, tokenId) < amounts[i]) revert InsufficientBalance();

            // Update accounting
            totalRedeemed[tokenId] += amounts[i];
            _totalSupply[tokenId] -= amounts[i];

            emit OutcomeTokensBurned(proposalIds[i], from, isPassFlags[i], amounts[i]);
        }

        _burnBatch(from, tokenIds, amounts);
    }

    // =============================================================
    //                       VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get the balance of outcome tokens for an account
     * @param account The address to query
     * @param proposalId The proposal ID
     * @param isPass True for PASS tokens, false for FAIL tokens
     * @return balance The token balance
     */
    function balanceOfOutcome(
        address account,
        uint256 proposalId,
        bool isPass
    ) external view returns (uint256) {
        return balanceOf(account, getTokenId(proposalId, isPass));
    }

    /**
     * @notice Get the total supply of outcome tokens
     * @param proposalId The proposal ID
     * @param isPass True for PASS tokens, false for FAIL tokens
     * @return supply The total supply (minted - redeemed)
     */
    function totalSupplyOfOutcome(uint256 proposalId, bool isPass) external view returns (uint256) {
        return _totalSupply[getTokenId(proposalId, isPass)];
    }

    /**
     * @notice Get the total supply for a token ID
     * @param tokenId The ERC1155 token ID
     * @return supply The total supply
     */
    function totalSupply(uint256 tokenId) external view returns (uint256) {
        return _totalSupply[tokenId];
    }

    /**
     * @notice Check if a token ID exists (has been minted)
     * @param tokenId The ERC1155 token ID
     * @return exists True if tokens have been minted
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return totalMinted[tokenId] > 0;
    }

    // =============================================================
    //                      UUPS UPGRADE
    // =============================================================

    /**
     * @notice Authorize contract upgrades
     * @dev Only treasury can upgrade (treasury is controlled by governance)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyTreasury {
        // Treasury (controlled by governance/timelock) authorizes upgrades
        (newImplementation); // Silence unused parameter warning
    }

    // =============================================================
    //                    ERC1155 OVERRIDES
    // =============================================================

    /**
     * @notice Check if contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
