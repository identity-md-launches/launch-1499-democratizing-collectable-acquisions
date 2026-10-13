// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DCAToken} from "src/DCAToken.sol";

/// @dev Complements the existing unit suite with authorization boundaries and
/// properties about failed calls restoring allowances as well as balances.
/// forge-config: default.fuzz.runs = 1000
contract DCATokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    DCAToken internal token;
    address internal alice = makeAddr("adversarial alice");
    address internal bob = makeAddr("adversarial bob");
    address internal spender = makeAddr("adversarial spender");

    function setUp() public {
        token = new DCAToken();
    }

    function test_oneMinorUnitCanMakeARoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_maximumTransferFromRestoresFiniteApproval() public {
        _assertMaximumTransferFromRejected(type(uint256).max - 1);
    }

    function test_maximumTransferFromRestoresInfiniteApproval() public {
        _assertMaximumTransferFromRejected(type(uint256).max);
    }

    function _assertMaximumTransferFromRejected(uint256 approved) internal {
        assertTrue(token.approve(spender, approved));
        bytes memory expected = approved == type(uint256).max
            ? abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
            : abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, type(uint256).max
            );
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), approved);
        _assertInitialBalances();
    }

    function test_transferFromByHolderStillRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        _assertInitialBalances();

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_anotherSpenderCannotUseAnApproval() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), bob), 0);
        _assertInitialBalances();
    }

    function test_infiniteApprovalCanBeRevokedAndReplaced() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertInitialBalances();

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_approvalSurvivesEmptyBalanceAndCanSpendLaterReceipts() public {
        assertTrue(token.approve(spender, 1));
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroDelegatedTransferToZeroRevertsWithoutApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function testFuzz_overAllowanceRevertsAcrossUint256Domain(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, approved + 1, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_overBalanceRestoresApproval(uint256 held, uint256 amount, bool infinite) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        assertTrue(token.transfer(alice, held));
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientRestoresApproval(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_delegatedRoundTripPreservesBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), amount));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function _assertInitialBalances() internal view {
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
