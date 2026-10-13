// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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

    /// @dev Explicit modes keep revocation, infinite approval, and spendable finite
    /// allowances reachable instead of mostly generating enormous allowances.
    function configureAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 mode, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : bound(amount, 0, expectedBalance[owner]);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: the invariant checks every balance and allowance after rejection.
    }

    function rejectTransferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        // Replace an infinite allowance so that an allowance failure is possible.
        if (allowance == type(uint256).max) {
            vm.prank(from);
            assertTrue(token.approve(spender, 0));
            expectedAllowance[from][spender] = 0;
            allowance = 0;
        }
        amount = bound(amount, allowance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectTransferFromOverBalance(
        uint256 spenderSeed,
        uint256 fromSeed,
        uint256 toSeed,
        uint256 amount,
        bool infinite
    ) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        uint256 allowance = infinite ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, allowance));
        expectedAllowance[from][spender] = allowance;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroRecipient(uint256 spenderSeed, uint256 fromSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < available) {
            available = expectedAllowance[from][spender];
        }
        amount = bound(amount, 0, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
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

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
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

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.configureAllowance.selector;
        selectors[4] = handler.transferAll.selector;
        selectors[5] = handler.rejectTransferOverBalance.selector;
        selectors[6] = handler.rejectTransferFromOverAllowance.selector;
        selectors[7] = handler.rejectTransferFromOverBalance.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
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
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev After arbitrary operations, every holder can still move its entire
    /// balance. Gathering all balances also checks that repeated drains lose no dust.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transferAll(i, 0);
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_balancesMatchLedgerAndConserveSupply();
        invariant_allowancesMatchLedger();
        invariant_supplyIsFixedAndNeverAssignedToZero();
    }

    function test_handlerSequenceExercisesBoundariesAndFailureRecovery() public {
        handler.transferAll(0, 1);
        handler.configureAllowance(1, 2, 2, 3);
        handler.transferFrom(2, 1, 3, 1);
        assertEq(token.allowance(actors[1], actors[2]), 2);
        handler.rejectTransferFromOverAllowance(2, 1, 3, 3);
        handler.rejectTransferOverBalance(3, 0, 2);
        handler.rejectTransferFromOverBalance(2, 1, 3, SUPPLY, false);
        handler.rejectZeroRecipient(2, 1, 1, true);
        handler.rejectZeroRecipient(2, 1, 0, false);
        handler.rejectZeroSpender(1, type(uint256).max);
        handler.configureAllowance(1, 2, 1, 0);
        handler.rejectTransferFromOverBalance(2, 1, 3, SUPPLY, true);
        handler.transferFrom(2, 1, 3, 1);
        assertEq(token.allowance(actors[1], actors[2]), type(uint256).max);
        handler.configureAllowance(1, 2, 0, 0);
        handler.rejectTransferFromOverAllowance(2, 1, 3, 1);
        afterInvariant();
    }
}
