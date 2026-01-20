// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ConditionalTokensTest
 * @notice Unit tests for the ConditionalTokens ERC-1155 contract
 * @dev Tests invariants CTK-1 through CTK-9
 */
contract ConditionalTokensTest is Test {
    ConditionalTokens public implementation;
    ConditionalTokens public tokens;

    address public treasury = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public attacker = address(0x4);

    uint256 constant PROPOSAL_ID_1 = 1;
    uint256 constant PROPOSAL_ID_2 = 2;

    function setUp() public {
        // Deploy implementation
        implementation = new ConditionalTokens();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            ConditionalTokens.initialize.selector,
            ""
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        tokens = ConditionalTokens(address(proxy));

        // Set treasury
        tokens.setTreasury(treasury);
    }

    // =============================================================
    //                    TOKEN ID TESTS
    // =============================================================

    /// @notice CTK-3: Token ID is deterministic: keccak256(proposalId, isPass)
    function test_TokenIdDeterministic() public view {
        uint256 tokenId1 = tokens.getTokenId(PROPOSAL_ID_1, true);
        uint256 tokenId2 = tokens.getTokenId(PROPOSAL_ID_1, true);
        assertEq(tokenId1, tokenId2, "Token ID should be deterministic");

        // Verify manual calculation
        uint256 expected = uint256(keccak256(abi.encodePacked(PROPOSAL_ID_1, true)));
        assertEq(tokenId1, expected, "Token ID should match keccak256");
    }

    /// @notice CTK-4: PASS and FAIL tokens have different token IDs for same proposal
    function test_PassFailDifferentIds() public view {
        uint256 passId = tokens.getTokenId(PROPOSAL_ID_1, true);
        uint256 failId = tokens.getTokenId(PROPOSAL_ID_1, false);
        assertTrue(passId != failId, "PASS and FAIL should have different IDs");
    }

    function test_GetPassTokenId() public view {
        uint256 passId = tokens.getPassTokenId(PROPOSAL_ID_1);
        uint256 expected = tokens.getTokenId(PROPOSAL_ID_1, true);
        assertEq(passId, expected);
    }

    function test_GetFailTokenId() public view {
        uint256 failId = tokens.getFailTokenId(PROPOSAL_ID_1);
        uint256 expected = tokens.getTokenId(PROPOSAL_ID_1, false);
        assertEq(failId, expected);
    }

    // =============================================================
    //                    TREASURY MANAGEMENT TESTS
    // =============================================================

    function test_SetTreasuryOnlyOnce() public {
        // Treasury already set in setUp
        vm.expectRevert(ConditionalTokens.TreasuryAlreadySet.selector);
        tokens.setTreasury(user1);
    }

    function test_SetTreasuryZeroAddress() public {
        // Deploy fresh contract
        ConditionalTokens fresh = new ConditionalTokens();
        bytes memory initData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy proxy = new ERC1967Proxy(address(fresh), initData);
        ConditionalTokens freshTokens = ConditionalTokens(address(proxy));

        vm.expectRevert(ConditionalTokens.ZeroAddress.selector);
        freshTokens.setTreasury(address(0));
    }

    function test_TreasurySetEvent() public {
        ConditionalTokens fresh = new ConditionalTokens();
        bytes memory initData = abi.encodeWithSelector(ConditionalTokens.initialize.selector, "");
        ERC1967Proxy proxy = new ERC1967Proxy(address(fresh), initData);
        ConditionalTokens freshTokens = ConditionalTokens(address(proxy));

        vm.expectEmit(true, false, false, false);
        emit ConditionalTokens.TreasurySet(treasury);
        freshTokens.setTreasury(treasury);
    }

    // =============================================================
    //                    MINT TESTS (CTK-1)
    // =============================================================

    /// @notice CTK-1: Only FutarchyTreasury can mint tokens
    function test_MintOnlyTreasury() public {
        vm.prank(attacker);
        vm.expectRevert(ConditionalTokens.OnlyTreasury.selector);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);
    }

    function test_MintSuccess() public {
        uint256 amount = 1000e18;

        vm.prank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, amount);

        // Check balance
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), amount);

        // Check total supply tracking
        assertEq(tokens.totalSupplyOfOutcome(PROPOSAL_ID_1, true), amount);
        assertEq(tokens.totalMinted(tokens.getTokenId(PROPOSAL_ID_1, true)), amount);
    }

    function test_MintZeroAmount() public {
        vm.prank(treasury);
        vm.expectRevert(ConditionalTokens.ZeroAmount.selector);
        tokens.mint(user1, PROPOSAL_ID_1, true, 0);
    }

    function test_MintZeroAddress() public {
        vm.prank(treasury);
        vm.expectRevert(ConditionalTokens.ZeroAddress.selector);
        tokens.mint(address(0), PROPOSAL_ID_1, true, 100e18);
    }

    function test_MintEvent() public {
        vm.prank(treasury);
        vm.expectEmit(true, true, false, true);
        emit ConditionalTokens.OutcomeTokensMinted(PROPOSAL_ID_1, user1, true, 100e18);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);
    }

    function test_MintMultipleUsers() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);
        tokens.mint(user2, PROPOSAL_ID_1, true, 200e18);
        vm.stopPrank();

        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), 100e18);
        assertEq(tokens.balanceOfOutcome(user2, PROPOSAL_ID_1, true), 200e18);
        assertEq(tokens.totalSupplyOfOutcome(PROPOSAL_ID_1, true), 300e18);
    }

    // =============================================================
    //                    BURN TESTS (CTK-1)
    // =============================================================

    /// @notice CTK-1: Only FutarchyTreasury can burn tokens
    function test_BurnOnlyTreasury() public {
        // First mint some tokens
        vm.prank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        // Try to burn as attacker
        vm.prank(attacker);
        vm.expectRevert(ConditionalTokens.OnlyTreasury.selector);
        tokens.burn(user1, PROPOSAL_ID_1, true, 50e18);
    }

    function test_BurnSuccess() public {
        uint256 mintAmount = 1000e18;
        uint256 burnAmount = 400e18;

        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, mintAmount);
        tokens.burn(user1, PROPOSAL_ID_1, true, burnAmount);
        vm.stopPrank();

        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), mintAmount - burnAmount);
        assertEq(tokens.totalSupplyOfOutcome(PROPOSAL_ID_1, true), mintAmount - burnAmount);

        uint256 tokenId = tokens.getTokenId(PROPOSAL_ID_1, true);
        assertEq(tokens.totalMinted(tokenId), mintAmount);
        assertEq(tokens.totalRedeemed(tokenId), burnAmount);
    }

    function test_BurnInsufficientBalance() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        vm.expectRevert(ConditionalTokens.InsufficientBalance.selector);
        tokens.burn(user1, PROPOSAL_ID_1, true, 200e18);
        vm.stopPrank();
    }

    function test_BurnZeroAmount() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        vm.expectRevert(ConditionalTokens.ZeroAmount.selector);
        tokens.burn(user1, PROPOSAL_ID_1, true, 0);
        vm.stopPrank();
    }

    function test_BurnEvent() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        vm.expectEmit(true, true, false, true);
        emit ConditionalTokens.OutcomeTokensBurned(PROPOSAL_ID_1, user1, true, 50e18);
        tokens.burn(user1, PROPOSAL_ID_1, true, 50e18);
        vm.stopPrank();
    }

    // =============================================================
    //                    BATCH MINT/BURN TESTS
    // =============================================================

    function test_MintBatchSuccess() public {
        uint256[] memory proposalIds = new uint256[](3);
        proposalIds[0] = PROPOSAL_ID_1;
        proposalIds[1] = PROPOSAL_ID_1;
        proposalIds[2] = PROPOSAL_ID_2;

        bool[] memory isPassFlags = new bool[](3);
        isPassFlags[0] = true;
        isPassFlags[1] = false;
        isPassFlags[2] = true;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e18;
        amounts[1] = 200e18;
        amounts[2] = 300e18;

        vm.prank(treasury);
        tokens.mintBatch(user1, proposalIds, isPassFlags, amounts);

        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), 100e18);
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, false), 200e18);
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_2, true), 300e18);
    }

    function test_BurnBatchSuccess() public {
        // First mint
        uint256[] memory proposalIds = new uint256[](2);
        proposalIds[0] = PROPOSAL_ID_1;
        proposalIds[1] = PROPOSAL_ID_1;

        bool[] memory isPassFlags = new bool[](2);
        isPassFlags[0] = true;
        isPassFlags[1] = false;

        uint256[] memory mintAmounts = new uint256[](2);
        mintAmounts[0] = 500e18;
        mintAmounts[1] = 500e18;

        vm.startPrank(treasury);
        tokens.mintBatch(user1, proposalIds, isPassFlags, mintAmounts);

        // Then burn
        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = 200e18;
        burnAmounts[1] = 300e18;

        tokens.burnBatch(user1, proposalIds, isPassFlags, burnAmounts);
        vm.stopPrank();

        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), 300e18);
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, false), 200e18);
    }

    // =============================================================
    //                    INVARIANT: CTK-2
    // =============================================================

    /// @notice CTK-2: totalMinted - totalRedeemed == totalSupply
    function test_Invariant_SupplyAccounting() public {
        vm.startPrank(treasury);

        // Multiple mints and burns
        tokens.mint(user1, PROPOSAL_ID_1, true, 1000e18);
        tokens.mint(user2, PROPOSAL_ID_1, true, 500e18);
        tokens.burn(user1, PROPOSAL_ID_1, true, 300e18);
        tokens.mint(user1, PROPOSAL_ID_1, true, 200e18);
        tokens.burn(user2, PROPOSAL_ID_1, true, 100e18);

        vm.stopPrank();

        uint256 tokenId = tokens.getTokenId(PROPOSAL_ID_1, true);
        uint256 minted = tokens.totalMinted(tokenId);
        uint256 redeemed = tokens.totalRedeemed(tokenId);
        uint256 supply = tokens.totalSupply(tokenId);

        assertEq(minted - redeemed, supply, "CTK-2: totalMinted - totalRedeemed != totalSupply");
    }

    // =============================================================
    //                    VIEW FUNCTION TESTS
    // =============================================================

    function test_BalanceOfOutcome() public {
        vm.prank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), 100e18);
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, false), 0);
        assertEq(tokens.balanceOfOutcome(user2, PROPOSAL_ID_1, true), 0);
    }

    function test_TotalSupplyOfOutcome() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);
        tokens.mint(user2, PROPOSAL_ID_1, true, 200e18);
        vm.stopPrank();

        assertEq(tokens.totalSupplyOfOutcome(PROPOSAL_ID_1, true), 300e18);
        assertEq(tokens.totalSupplyOfOutcome(PROPOSAL_ID_1, false), 0);
    }

    function test_Exists() public {
        uint256 tokenId = tokens.getTokenId(PROPOSAL_ID_1, true);
        assertFalse(tokens.exists(tokenId));

        vm.prank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        assertTrue(tokens.exists(tokenId));
    }

    // =============================================================
    //                    ERC1155 TRANSFER TESTS (CTK-9)
    // =============================================================

    /// @notice CTK-9: ERC1155 transfer functions work correctly
    function test_SafeTransferFrom() public {
        vm.prank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);

        uint256 tokenId = tokens.getTokenId(PROPOSAL_ID_1, true);

        vm.prank(user1);
        tokens.safeTransferFrom(user1, user2, tokenId, 40e18, "");

        assertEq(tokens.balanceOf(user1, tokenId), 60e18);
        assertEq(tokens.balanceOf(user2, tokenId), 40e18);
    }

    function test_SafeBatchTransferFrom() public {
        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, 100e18);
        tokens.mint(user1, PROPOSAL_ID_1, false, 200e18);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = tokens.getTokenId(PROPOSAL_ID_1, true);
        ids[1] = tokens.getTokenId(PROPOSAL_ID_1, false);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30e18;
        amounts[1] = 50e18;

        vm.prank(user1);
        tokens.safeBatchTransferFrom(user1, user2, ids, amounts, "");

        assertEq(tokens.balanceOf(user1, ids[0]), 70e18);
        assertEq(tokens.balanceOf(user1, ids[1]), 150e18);
        assertEq(tokens.balanceOf(user2, ids[0]), 30e18);
        assertEq(tokens.balanceOf(user2, ids[1]), 50e18);
    }

    // =============================================================
    //                    UUPS UPGRADE TESTS
    // =============================================================

    function test_UpgradeOnlyTreasury() public {
        // Deploy new implementation
        ConditionalTokens newImpl = new ConditionalTokens();

        // Non-treasury cannot upgrade
        vm.prank(attacker);
        vm.expectRevert(ConditionalTokens.OnlyTreasury.selector);
        tokens.upgradeToAndCall(address(newImpl), "");

        // Treasury can upgrade
        vm.prank(treasury);
        tokens.upgradeToAndCall(address(newImpl), "");
    }

    // =============================================================
    //                    FUZZ TESTS
    // =============================================================

    function testFuzz_MintBurnAccounting(
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        // Bound inputs to reasonable values
        mintAmount = bound(mintAmount, 1, type(uint128).max);
        burnAmount = bound(burnAmount, 0, mintAmount);

        vm.startPrank(treasury);
        tokens.mint(user1, PROPOSAL_ID_1, true, mintAmount);

        if (burnAmount > 0) {
            tokens.burn(user1, PROPOSAL_ID_1, true, burnAmount);
        }
        vm.stopPrank();

        // Verify invariant
        uint256 tokenId = tokens.getTokenId(PROPOSAL_ID_1, true);
        uint256 expectedSupply = mintAmount - burnAmount;

        assertEq(tokens.totalSupply(tokenId), expectedSupply);
        assertEq(tokens.balanceOfOutcome(user1, PROPOSAL_ID_1, true), expectedSupply);
    }

    function testFuzz_TokenIdUniqueness(
        uint256 proposalId1,
        uint256 proposalId2,
        bool isPass1,
        bool isPass2
    ) public view {
        // Skip if same inputs
        vm.assume(proposalId1 != proposalId2 || isPass1 != isPass2);

        uint256 id1 = tokens.getTokenId(proposalId1, isPass1);
        uint256 id2 = tokens.getTokenId(proposalId2, isPass2);

        assertTrue(id1 != id2, "Different inputs should produce different token IDs");
    }
}
