// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";

/// @notice Boundary and sequence properties complement the core ERC-20 suite.
/// forge-config: default.fuzz.runs = 1000
contract VerdictIMDBoundariesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    VerdictIMD private token;
    address private holder;
    address private recipient;
    address private spender;

    function setUp() public {
        token = new VerdictIMD();
        holder = makeAddr("boundary holder");
        recipient = makeAddr("boundary recipient");
        spender = makeAddr("boundary spender");
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function test_oneWeiCanBeTransferredAndSpentWithExactApproval() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        vm.prank(recipient);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumFiniteAllowanceIsDecremented() public {
        uint256 approved = type(uint256).max - 1;
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), approved - 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_maximumTransferRevertsAndPreservesInfiniteApproval() public {
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReplacedAndRevokedAfterUse() public {
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.prank(holder);
        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 1);
        vm.prank(holder);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 2);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_infiniteApprovalStillRejectsZeroRecipientForZeroAndFullSupply() public {
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), SUPPLY);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalSupportsFullUint256Range(uint256 approved) public {
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_partialBalanceFailurePreservesFiniteAllowance(uint256 rawBalance, uint256 rawApproval) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY - balance));
        uint256 approved = bound(rawApproval, balance + 1, type(uint256).max - 1);
        vm.prank(holder);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, balance + 1)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, balance + 1);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // Splitting a transfer must have the same outcome as sending the total once.
    // This also checks that intervening transfers do not consume an approval.
    function testFuzz_splitTransfersEqualSingleTransfer(uint256 rawTotal, uint256 rawFirst) public {
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        vm.prank(holder);
        token.approve(spender, total);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, first));
        vm.prank(holder);
        assertTrue(token.transfer(recipient, total - first));
        assertEq(token.balanceOf(holder), SUPPLY - total);
        assertEq(token.balanceOf(recipient), total);
        assertEq(token.allowance(holder, spender), total);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, total));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, total));
        assertEq(token.balanceOf(holder), SUPPLY - total);
        assertEq(token.balanceOf(recipient), total);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_twoSpendersHaveIndependentBudgets(uint256 rawFirst, uint256 rawSecond) public {
        address otherSpender = makeAddr("second boundary spender");
        uint256 first = bound(rawFirst, 1, SUPPLY - 1);
        uint256 second = bound(rawSecond, 1, SUPPLY - first);
        vm.startPrank(holder);
        token.approve(spender, first);
        token.approve(otherSpender, second);
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, otherSpender), second);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, otherSpender), second);
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(holder, recipient, second));
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(recipient), first + second);
        assertEq(token.balanceOf(holder), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
