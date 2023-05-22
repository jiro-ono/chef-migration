// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "utils/BaseTest.sol";

import "interfaces/IMiniChefV2.sol";
import "/MiniChefMigrator.sol";

import {console2} from "forge-std/console2.sol";

contract SimpleMigratorTest is BaseTest {
    IMiniChefV2 public minichef;
    MiniChefMigrator public migrator;

    function setUp() public override {
        forkPolygon(37729882);
        super.setUp();



        minichef = IMiniChefV2(constants.getAddress("polygon.minichef"));
        migrator = new MiniChefMigrator(address(minichef));
    }

    function testPoolLength() public {
        uint256 poolLength = minichef.poolLength();
        console2.log("poolLength: %s", poolLength);
    }

    function testMigrate() public {
        // set migrator contract to minichef
        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        minichef.migrate(0);
        vm.stopPrank();
    }
}