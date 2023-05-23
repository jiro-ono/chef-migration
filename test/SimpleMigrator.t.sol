// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";

import "interfaces/IMiniChefV2.sol";
import "interfaces/IERC20.sol";
import "/MiniChefMigrator.sol";

import {console2} from "forge-std/console2.sol";

contract SimpleMigratorTest is BaseTest {
    IMiniChefV2 public minichef;
    MiniChefMigrator public migrator;

    function setUp() public override {
        forkPolygon(37729882);
        super.setUp();



        minichef = IMiniChefV2(constants.getAddress("polygon.minichef"));
        migrator = new MiniChefMigrator(address(minichef), address(constants.getAddress("polygon.v3migrator")));
    }

    function testPoolLength() public {
        uint256 poolLength = minichef.poolLength();
        console2.log("poolLength: %s", poolLength);
    }

    function testMigrate() public {
        IUniswapV2Pair lpToken = IUniswapV2Pair(minichef.lpToken(0));
        IERC20 token0 = IERC20(lpToken.token0());
        IERC20 token1 = IERC20(lpToken.token1());

        // set migrator contract to minichef
        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        minichef.migrate(0);
        vm.stopPrank();

        console2.log("token0: %s", token0.balanceOf(address(0x7812BCD0c0De8D15Ff4C47391d2d9AE1B4DE13f0)));
        console2.log("token1: %s", token1.balanceOf(address(0x7812BCD0c0De8D15Ff4C47391d2d9AE1B4DE13f0)));
    }
}