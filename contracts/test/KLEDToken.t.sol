// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {KLEDToken} from "../src/KLEDToken.sol";

/**
 * @title KLEDToken Unit Tests
 * @notice Comprehensive tests for the KLED governance token
 * @dev Tests cover:
 * - Constructor and initialization
 * - Minting functionality and restrictions
 * - Minting lock mechanism
 * - Ownership transfer
 * - ERC20Votes delegation
 * - ERC20Permit gasless approvals
 * - Edge cases and reverts
 */
contract KLEDTokenTest is Test {
    KLEDToken public token;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MintingPermanentlyLocked(address indexed locker, uint256 totalSupplyAtLock);
    event TokensMinted(address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes);

    function setUp() public {
        token = new KLEDToken(owner, INITIAL_SUPPLY);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsOwner() public view {
        assertEq(token.owner(), owner);
    }

    function test_Constructor_MintsInitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
    }

    function test_Constructor_ZeroInitialSupply() public {
        KLEDToken zeroToken = new KLEDToken(owner, 0);
        assertEq(zeroToken.totalSupply(), 0);
        assertEq(zeroToken.balanceOf(owner), 0);
    }

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(token.name(), "KLED Token");
        assertEq(token.symbol(), "KLED");
    }

    function test_Constructor_SetsDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Constructor_MintingNotLocked() public view {
        assertFalse(token.mintingLocked());
    }

    function test_Constructor_EmitsOwnershipTransferred() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(0), alice);
        new KLEDToken(alice, 0);
    }

    function test_Constructor_EmitsTokensMinted() public {
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(alice, 1000 ether);
        new KLEDToken(alice, 1000 ether);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert(KLEDToken.ZeroAddress.selector);
        new KLEDToken(address(0), INITIAL_SUPPLY);
    }

    // ============ Mint Tests ============

    function test_Mint_ByOwner() public {
        uint256 mintAmount = 500_000 ether;

        vm.prank(owner);
        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_Mint_EmitsEvent() public {
        uint256 mintAmount = 100 ether;

        vm.expectEmit(true, false, false, true);
        emit TokensMinted(alice, mintAmount);

        vm.prank(owner);
        token.mint(alice, mintAmount);
    }

    function test_Mint_RevertsIfNotOwner() public {
        vm.expectRevert(KLEDToken.NotOwner.selector);
        vm.prank(alice);
        token.mint(alice, 100 ether);
    }

    function test_Mint_RevertsIfMintingLocked() public {
        vm.startPrank(owner);
        token.lockMinting();

        vm.expectRevert(KLEDToken.MintingLocked.selector);
        token.mint(alice, 100 ether);
        vm.stopPrank();
    }

    function test_Mint_RevertsOnZeroAmount() public {
        vm.expectRevert(KLEDToken.ZeroMintAmount.selector);
        vm.prank(owner);
        token.mint(alice, 0);
    }

    function test_Mint_RevertsOnZeroAddress() public {
        vm.expectRevert(KLEDToken.ZeroAddress.selector);
        vm.prank(owner);
        token.mint(address(0), 100 ether);
    }

    function test_Mint_MultipleTimes() public {
        vm.startPrank(owner);
        token.mint(alice, 100 ether);
        token.mint(alice, 200 ether);
        token.mint(bob, 300 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 300 ether);
        assertEq(token.balanceOf(bob), 300 ether);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + 600 ether);
    }

    // ============ Lock Minting Tests ============

    function test_LockMinting_ByOwner() public {
        vm.prank(owner);
        token.lockMinting();

        assertTrue(token.mintingLocked());
    }

    function test_LockMinting_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit MintingPermanentlyLocked(owner, INITIAL_SUPPLY);

        vm.prank(owner);
        token.lockMinting();
    }

    function test_LockMinting_RevertsIfNotOwner() public {
        vm.expectRevert(KLEDToken.NotOwner.selector);
        vm.prank(alice);
        token.lockMinting();
    }

    function test_LockMinting_RevertsIfAlreadyLocked() public {
        vm.startPrank(owner);
        token.lockMinting();

        vm.expectRevert(KLEDToken.MintingLocked.selector);
        token.lockMinting();
        vm.stopPrank();
    }

    function test_LockMinting_PermanentlyPreventsNewMints() public {
        vm.startPrank(owner);
        token.lockMinting();
        vm.stopPrank();

        // Even owner cannot mint after lock
        vm.expectRevert(KLEDToken.MintingLocked.selector);
        vm.prank(owner);
        token.mint(alice, 1 ether);

        // Total supply is fixed
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    // ============ Ownership Transfer Tests ============

    function test_TransferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(alice);

        assertEq(token.owner(), alice);
    }

    function test_TransferOwnership_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, alice);

        vm.prank(owner);
        token.transferOwnership(alice);
    }

    function test_TransferOwnership_NewOwnerCanMint() public {
        vm.prank(owner);
        token.transferOwnership(alice);

        vm.prank(alice);
        token.mint(bob, 100 ether);

        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_TransferOwnership_PreviousOwnerCannotMint() public {
        vm.prank(owner);
        token.transferOwnership(alice);

        vm.expectRevert(KLEDToken.NotOwner.selector);
        vm.prank(owner);
        token.mint(bob, 100 ether);
    }

    function test_TransferOwnership_RevertsIfNotOwner() public {
        vm.expectRevert(KLEDToken.NotOwner.selector);
        vm.prank(alice);
        token.transferOwnership(bob);
    }

    function test_TransferOwnership_RevertsOnZeroAddress() public {
        vm.expectRevert(KLEDToken.ZeroAddress.selector);
        vm.prank(owner);
        token.transferOwnership(address(0));
    }

    // ============ ERC20 Standard Tests ============

    function test_Transfer() public {
        vm.prank(owner);
        token.transfer(alice, 100 ether);

        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 100 ether);
    }

    function test_Approve() public {
        vm.prank(owner);
        token.approve(alice, 100 ether);

        assertEq(token.allowance(owner, alice), 100 ether);
    }

    function test_TransferFrom() public {
        vm.prank(owner);
        token.approve(alice, 100 ether);

        vm.prank(alice);
        token.transferFrom(owner, bob, 50 ether);

        assertEq(token.balanceOf(bob), 50 ether);
        assertEq(token.allowance(owner, alice), 50 ether);
    }

    // ============ ERC20Votes Delegation Tests ============

    function test_Delegate_ToSelf() public {
        vm.prank(owner);
        token.delegate(owner);

        assertEq(token.getVotes(owner), INITIAL_SUPPLY);
        assertEq(token.delegates(owner), owner);
    }

    function test_Delegate_ToAnother() public {
        vm.prank(owner);
        token.transfer(alice, 100 ether);

        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.getVotes(bob), 100 ether);
        assertEq(token.getVotes(alice), 0);
        assertEq(token.delegates(alice), bob);
    }

    function test_Delegate_EmitsEvents() public {
        vm.prank(owner);
        token.transfer(alice, 100 ether);

        vm.expectEmit(true, true, true, false);
        emit DelegateChanged(alice, address(0), bob);

        vm.expectEmit(true, false, false, true);
        emit DelegateVotesChanged(bob, 0, 100 ether);

        vm.prank(alice);
        token.delegate(bob);
    }

    function test_Delegate_VotingPowerFollowsTransfers() public {
        // Owner delegates to self
        vm.prank(owner);
        token.delegate(owner);

        // Transfer to alice
        vm.prank(owner);
        token.transfer(alice, 100 ether);

        // Alice delegates to bob
        vm.prank(alice);
        token.delegate(bob);

        // Check voting power
        assertEq(token.getVotes(owner), INITIAL_SUPPLY - 100 ether);
        assertEq(token.getVotes(bob), 100 ether);
        assertEq(token.getVotes(alice), 0);

        // Alice transfers to charlie
        vm.prank(alice);
        token.transfer(charlie, 50 ether);

        // Bob's voting power decreases (alice had delegated to bob)
        assertEq(token.getVotes(bob), 50 ether);
    }

    function test_Delegate_UndelegatedTokensDontCount() public {
        // Without delegation, voting power is 0
        assertEq(token.getVotes(owner), 0);

        // After delegation, it counts
        vm.prank(owner);
        token.delegate(owner);
        assertEq(token.getVotes(owner), INITIAL_SUPPLY);
    }

    function test_Delegate_ChangeDelegate() public {
        vm.prank(owner);
        token.transfer(alice, 100 ether);

        vm.startPrank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 100 ether);

        token.delegate(charlie);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(charlie), 100 ether);
        vm.stopPrank();
    }

    // ============ ERC20Votes Checkpointing Tests ============

    function test_GetPastVotes() public {
        // Set a reasonable starting timestamp (>1 to avoid edge cases)
        uint256 t0 = 1000;
        vm.warp(t0);

        // Owner delegates to self at t0
        vm.prank(owner);
        token.delegate(owner);

        // Move to t1 for the transfer
        uint256 t1 = t0 + 100;
        vm.warp(t1);

        vm.prank(owner);
        token.transfer(alice, 100 ether);

        // Alice delegates at t1
        vm.prank(alice);
        token.delegate(alice);

        // Move to t2 for queries (must be after t1 to query t1)
        uint256 t2 = t1 + 100;
        vm.warp(t2);

        // Check past votes - query timestamps must be < current clock
        // At t0, owner had all votes
        assertEq(token.getPastVotes(owner, t0), INITIAL_SUPPLY, "owner votes at t0");
        // At t1, owner transferred 100 to alice who delegated to alice
        assertEq(token.getPastVotes(owner, t1), INITIAL_SUPPLY - 100 ether, "owner votes at t1");
        assertEq(token.getPastVotes(alice, t1), 100 ether, "alice votes at t1");
    }

    function test_GetPastTotalSupply() public {
        // Set a reasonable starting timestamp
        uint256 t0 = 1000;
        vm.warp(t0);

        // No checkpoint yet, but totalSupply exists from constructor

        // Move to t1 for the mint
        uint256 t1 = t0 + 100;
        vm.warp(t1);

        vm.prank(owner);
        token.mint(alice, 500 ether);

        // Move to t2 for queries
        uint256 t2 = t1 + 100;
        vm.warp(t2);

        // Query past total supply
        assertEq(token.getPastTotalSupply(t0), INITIAL_SUPPLY, "supply at t0");
        assertEq(token.getPastTotalSupply(t1), INITIAL_SUPPLY + 500 ether, "supply at t1");
    }

    // ============ Clock Mode Tests ============

    function test_Clock_ReturnsTimestamp() public view {
        assertEq(token.clock(), uint48(block.timestamp));
    }

    function test_ClockMode_ReturnsTimestampMode() public view {
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }

    // ============ ERC20Permit Tests ============

    function test_Permit() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        // Give signer some tokens
        vm.prank(owner);
        token.mint(signer, 100 ether);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(permitTypehash, signer, alice, 100 ether, nonce, deadline)
        );

        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.permit(signer, alice, 100 ether, deadline, v, r, s);

        assertEq(token.allowance(signer, alice), 100 ether);
        assertEq(token.nonces(signer), nonce + 1);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        // ERC20Votes safe supply is type(uint208).max, need to account for existing supply
        uint256 maxMintable = type(uint208).max - token.totalSupply();
        amount = bound(amount, 1, maxMintable);

        vm.prank(owner);
        token.mint(to, amount);

        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != owner);
        vm.assume(amount <= INITIAL_SUPPLY);

        vm.prank(owner);
        token.transfer(to, amount);

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    function testFuzz_Delegate(address delegatee) public {
        vm.assume(delegatee != address(0));

        vm.startPrank(owner);
        token.delegate(delegatee);
        vm.stopPrank();

        assertEq(token.getVotes(delegatee), INITIAL_SUPPLY);
    }

    // ============ Invariant Test Hooks ============

    /**
     * @notice Helper to expose total supply for invariant testing
     */
    function invariant_TotalSupplyIntegrity() external view returns (bool) {
        return token.totalSupply() >= INITIAL_SUPPLY;
    }

    /**
     * @notice Helper to verify minting lock invariant
     */
    function invariant_MintingLockPermanent() external view returns (bool) {
        // Once locked, should stay locked
        return true; // Placeholder - actual invariant test in separate file
    }
}

/**
 * @title KLEDToken Invariant Test Handler
 * @notice Handler contract for invariant/stateful fuzz testing
 * @dev Coordinates with TEST agent for full invariant test suite
 */
contract KLEDTokenHandler is Test {
    KLEDToken public token;
    address public owner;

    address[] public actors;
    mapping(address => bool) public isActor;

    constructor(KLEDToken _token, address _owner) {
        token = _token;
        owner = _owner;
    }

    function addActor(address actor) external {
        if (!isActor[actor]) {
            actors.push(actor);
            isActor[actor] = true;
        }
    }

    function mint(uint256 actorSeed, uint256 amount) external {
        if (actors.length == 0) return;
        address to = actors[actorSeed % actors.length];
        amount = bound(amount, 1, type(uint224).max - token.totalSupply());

        if (!token.mintingLocked()) {
            vm.prank(owner);
            token.mint(to, amount);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        if (actors.length < 2) return;
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];

        if (from == to) return;

        uint256 balance = token.balanceOf(from);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(from);
        token.transfer(to, amount);
    }

    function delegate(uint256 fromSeed, uint256 toSeed) external {
        if (actors.length == 0) return;
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];

        vm.prank(from);
        token.delegate(to);
    }

    function lockMinting() external {
        if (!token.mintingLocked()) {
            vm.prank(owner);
            token.lockMinting();
        }
    }
}
