// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";

import "interfaces/IMiniChefV2.sol";
import "/MiniChefMigrator.sol";

import {console2} from "forge-std/console2.sol";

contract SimpleMigratorTest is BaseTest {
    IMiniChefV2 public minichef;
    MiniChefMigrator public migrator;
    V3Migrator public v3Migrator;
    NonfungiblePositionManager public positionManager;

    IUniswapV3Pool public testPool;

    function setUp() public override {
        forkPolygon(43063420);
        super.setUp();

        testPool = IUniswapV3Pool(0xf1A12338D39Fc085D8631E1A745B5116BC9b2A32);
        console2.log("testPool: %s", address(testPool));
        console2.log("testPool fee: %s", testPool.fee());

        minichef = IMiniChefV2(constants.getAddress("polygon.minichef"));
        positionManager = new NonfungiblePositionManager(0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2, 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, 0x8c990A53e3fc5e4dB1404baB33C6DfaCEABfFEcc);
        v3Migrator = new V3Migrator(0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2, 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, address(positionManager));
        migrator = new MiniChefMigrator(address(minichef), address(v3Migrator));
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