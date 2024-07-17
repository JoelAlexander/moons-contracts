// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Moons} from "../src/Moons.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Test ERC20 Token", "TEST") {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MoonsTest is Test {
    Moons public moons;
    TestERC20 public testToken;
    address public admin1;
    address public admin2;
    address public participant1;
    address public participant2;
    address public participant3;
    address public participant4;

    function setUp() public {
        testToken = new TestERC20();

        admin1 = address(0x1);
        admin2 = address(0x2);
        participant1 = address(0x3);
        participant2 = address(0x4);
        participant3 = address(0x5);
        participant4 = address(0x6);

        vm.startPrank(admin1);
        moons = new Moons("Test Moons", "ipfs://constitution-hash", 1 days);
        moons.addAdmin(admin2, "Add second admin");
        moons.addParticipant(participant1, "Add participant 1");
        moons.addParticipant(participant2, "Add participant 2");
        moons.addParticipant(participant3, "Add participant 3");
        moons.addParticipant(participant4, "Add participant 4");
        vm.stopPrank();

        // Mint tokens to participants
        testToken.mint(participant1, 1000 ether);
        testToken.mint(participant2, 1000 ether);
        testToken.mint(participant3, 1000 ether);
        testToken.mint(participant4, 1000 ether);

        // Chain must be at least cycleTime old for Moons to allow disbursement
        // This may not be acceptible for niche use-cases, consider revising.
        vm.warp(block.timestamp + 1 days);
    }

    function testAddAdmin() public {
        vm.startPrank(admin2);
        moons.addAdmin(address(0x7), "Add admin 3");
        (address[] memory admins, uint256[] memory ranks) = moons.getAdmins();
        assertEq(admins[2], address(0x7));
        assertEq(ranks[2], 3);
        vm.stopPrank();
    }

    function testRemoveAdmin() public {
        vm.startPrank(admin1);
        moons.removeAdmin(admin2, "Remove second admin");
        (address[] memory admins, ) = moons.getAdmins();
        assertEq(admins.length, 1);
        vm.stopPrank();
    }

    function testAddParticipant() public {
        vm.startPrank(admin2);
        moons.addParticipant(address(0x7), "Add participant 5");
        (address[] memory participants, ) = moons.getParticipants();
        assertEq(participants[4], address(0x7));
        vm.stopPrank();
    }

    function testRemoveParticipant() public {
        vm.startPrank(admin1);
        moons.removeParticipant(participant1, "Remove participant 1");
        (address[] memory participants, ) = moons.getParticipants();
        assertEq(participants.length, 3);
        vm.stopPrank();
    }

    function testAddFunds() public {
        vm.prank(participant1);
        testToken.transfer(address(moons), 500 ether);
        assertEq(testToken.balanceOf(address(moons)), 500 ether);
    }

    function testDisburseFunds() public {
        vm.prank(participant1);
        testToken.transfer(address(moons), 500 ether);

        vm.warp(block.timestamp + 13 hours);

        vm.prank(participant1);
        moons.disburseFunds(address(testToken), 200 ether, "Disburse funds");
        assertEq(testToken.balanceOf(participant1), 700 ether);
    }

    function testSelfRemove() public {
        vm.prank(participant1);
        moons.removeParticipant(participant1, "Goodbye!");
    }

    function testDisburseOncePerCycle() public {
        vm.prank(participant1);
        testToken.transfer(address(moons), 500 ether);

        vm.warp(block.timestamp + 13 hours);

        vm.prank(participant1);
        moons.disburseFunds(address(testToken), 200 ether, "Disburse funds");

        vm.expectRevert("May only disburse funds once per cycle");
        vm.prank(participant1);
        moons.disburseFunds(address(testToken), 100 ether, "Disburse funds again");
    }

    function testAdminSeniority() public {
        vm.prank(admin1);
        moons.addAdmin(address(0x7), "Add admin 3");

        vm.startPrank(address(0x7));
        vm.expectRevert("Must have admin seniority");
        moons.removeAdmin(admin1, "Try to remove higher rank admin");
        vm.stopPrank();
    }

    function testParticipantRestriction() public {
        vm.expectRevert("Sender must be a participant");
        moons.disburseFunds(address(testToken), 500 ether, "Non-participant add funds");
    }

    function testMaximumAllowedDisbursment() public {
        vm.prank(participant1);
        testToken.transfer(address(moons), 500 ether);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(participant1);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 4259233868732866000);
        vm.prank(participant2);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 157351055745536550500);
        vm.prank(participant3);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 245738674586795570000);
        vm.prank(participant4);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 92646852457351913000);

        vm.warp(block.timestamp + 1 days);
        vm.prank(participant1);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 4259233868732866000);
        vm.prank(participant2);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 157351055745536550500);
        vm.prank(participant3);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 245738674586795570000);
        vm.prank(participant4);
        assertEq(moons.getMaximumAllowedDisbursement(address(testToken)), 92646852457351913000);
    }
}
