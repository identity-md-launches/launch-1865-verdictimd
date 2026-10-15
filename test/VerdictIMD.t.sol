// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";
import {TokenFactory, RejectingReceiver} from "./helpers/TokenFactory.sol";

contract VerdictIMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    VerdictIMD private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new VerdictIMD();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "VerdictIMD");
        assertEq(token.symbol(), "VERDICT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        VerdictIMD fresh = new VerdictIMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testFuzz_create2MintsToImmediateDeployer(bytes32 salt) public {
        TokenFactory factory = new TokenFactory();
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(VerdictIMD).creationCode))
                    )
                )
            )
        );
        vm.prank(alice, bob);
        VerdictIMD fresh = factory.deploy(salt);
        assertEq(address(fresh), predicted);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_transferEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupplyAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferToSelfPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferDoesNotCallRecipient() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1 ether));
        assertEq(token.balanceOf(address(receiver)), 1 ether);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferOverBalanceRevertsWithoutChanges(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromEmptyBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsAndOnlyChangesCallersAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveReplacesAndRevokesAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approveWithoutBalanceIsAllowed() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_transferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20 ether));
        assertEq(token.allowance(address(this), spender), 30 ether);
        assertEq(token.balanceOf(alice), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_transferFromExhaustsAllowance() public {
        token.approve(spender, 1 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_transferFromInfiniteAllowanceIsNotReduced() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSelfSpendsAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 6 ether);
    }

    function test_transferFromByHolderStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromWrongSpenderReverts() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 2 ether);
        vm.prank(alice);
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 2 ether, 3 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 3 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 2 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroRecipientRestoresAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 3 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromZeroSourceRevertsEvenForZeroAmount() public {
        // OZ checks the owner when spending the zero allowance, before the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAccountsExactly(uint256 rawAmount, uint256 rawApproval) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromOverAllowanceIsAtomic(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approval + 1, SUPPLY);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_launchAllocationsClaimsAndPoolTransfersAreExact() public {
        TokenFactory factory = new TokenFactory();
        VerdictIMD launched = factory.deploy(keccak256("launch flow test"));
        address distributor = makeAddr("distributor fixture");
        address poolManager = makeAddr("pool manager fixture");
        address remainderRecipient = makeAddr("remainder recipient fixture");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;

        assertTrue(factory.move(launched, distributor, swarmShare));
        assertTrue(factory.move(launched, poolManager, poolShare));
        assertTrue(factory.move(launched, remainderRecipient, SUPPLY - swarmShare - poolShare));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.balanceOf(remainderRecipient), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);
        vm.prank(poolManager);
        assertTrue(launched.transfer(bob, 10 ether));
        assertEq(launched.balanceOf(bob), 10 ether);
        assertEq(launched.balanceOf(poolManager), poolShare - 10 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(poolManager, 10 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(alice, 10 ether);
        bytes[] memory attempts = new bytes[](20);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", 1);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("issue(uint256)", 1);
        attempts[4] = abi.encodeWithSignature("initialize(address)", bob);
        attempts[5] = abi.encodeWithSignature("setMinter(address)", bob);
        attempts[6] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[7] = abi.encodeWithSignature("owner()");
        attempts[8] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[9] = abi.encodeWithSignature("pause()");
        attempts[10] = abi.encodeWithSignature("unpause()");
        attempts[11] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[12] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[13] = abi.encodeWithSignature("seize(address)", alice);
        attempts[14] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        attempts[15] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        attempts[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[17] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        attempts[18] = abi.encodeWithSignature("setOwner(address)", bob);
        attempts[19] = abi.encodeWithSignature("setTax(uint256)", 100);
        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool outsiderSucceeded,) = address(token).call(attempts[i]);
            assertFalse(outsiderSucceeded);
        }
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_runtimeHasNoForbiddenOpcodesAndFitsSizeLimit() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function test_plainEtherTransferIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
