// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DCAToken} from "../src/DCAToken.sol";

/// @dev Keeps an independent ledger for randomized, interleaved ERC-20 operations.
contract DCATokenHandler is Test {
    DCAToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(DCAToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }
}

contract DCATokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    DCAToken internal token;
    DCATokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new DCAToken();
        actors = [makeAddr("actor0"), makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
        token.transfer(actors[0], SUPPLY);
        handler = new DCATokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndNeverAssignedToZero() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesMatchLedgerAndConserveSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
    }

    function invariant_allowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
