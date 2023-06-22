// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";

import "v3-periphery/NonfungiblePositionManager.sol";

import "interfaces/IMiniChefV2.sol";
import "/MiniChefMigrator.sol";

import {console2} from "forge-std/console2.sol";

contract SimpleMigratorTest is BaseTest {
    IMiniChefV2 public minichef;
    MiniChefMigrator public migrator;
    V3Migrator public v3Migrator;
    IUniswapV3Factory public factory;
    NonfungiblePositionManager public positionManager;

    uint256 public totalPools;
    address public receipient = 0xeaf0227968E6EA31417734f36a7691FF2f779f81;

    function setUp() public override {
        forkPolygon();
        super.setUp();

        minichef = IMiniChefV2(constants.getAddress("polygon.minichef"));
        totalPools = minichef.poolLength();

        factory = IUniswapV3Factory(constants.getAddress("polygon.v3Factory"));
        positionManager = NonfungiblePositionManager(payable (constants.getAddress("polygon.positionManager")));
        v3Migrator = V3Migrator(payable (constants.getAddress("polygon.v3Migrator")));
        migrator = new MiniChefMigrator(address(minichef), address(v3Migrator), receipient);
    }

    function testPoolLength() public {
        assertEq(totalPools, minichef.poolLength());
    }

    function testMigrate(uint256 pid) public {
        vm.assume(pid < totalPools);
        console2.log("pid: ", pid);
        IUniswapV2Pair lpToken = IUniswapV2Pair(minichef.lpToken(pid));
        IERC20 token0 = IERC20(lpToken.token0());
        IERC20 token1 = IERC20(lpToken.token1());

        uint256 pre_lpTokenBalance = lpToken.balanceOf(address(minichef));
        uint256 preTotalPositions = positionManager.totalSupply();
        
        // set migrator contract to minichef
        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        
        // expected to revert if v3 pair hasn't been created yet
        if (factory.getPool(address(token0), address(token1), 500) == address(0)) {
            vm.expectRevert();
            minichef.migrate(pid);
            return;
        }

        minichef.migrate(pid);
        vm.stopPrank();

        assertEq(lpToken.balanceOf(address(minichef)), 0);
        assertEq(positionManager.balanceOf(address(receipient)), 1);
        assertEq(positionManager.totalSupply(), preTotalPositions + 1);
    }
}