// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "utils/BaseTest.sol";

import "interfaces/IMiniChefV2.sol";

import {console2} from "forge-std/console2.sol";

contract SimpleMigratorTest is BaseTest {
    IMiniChefV2 public miniChef;

    function setUp() public override {
        forkPolygon(37729882);
        super.setUp();

        miniChef = IMiniChefV2(constants.getAddress("polygon.minichef"));
    }

    function testPoolLength() public {
        uint256 poolLength = miniChef.poolLength();
        console2.log("poolLength: %s", poolLength);
    }
}