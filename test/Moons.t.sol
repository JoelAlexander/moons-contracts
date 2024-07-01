// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Moons} from "../src/Moons.sol";

contract MoonsTest is Test {
    Moons public moons;

    function setUp() public {
        moons = new Moons(0);
    }
}
