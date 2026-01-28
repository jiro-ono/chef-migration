// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMiniChefV2.sol";
import "/MiniChefMigratorTransfer.sol";

contract MigratorTransferTest is BaseTest {
    IMiniChefV2 public minichef;
    MiniChefMigratorTransfer public migrator;
    address public multisig = 0xeaf0227968E6EA31417734f36a7691FF2f779f81;

    function setUp() public override {
        forkPolygon();
        super.setUp();
        minichef = IMiniChefV2(constants.getAddress("polygon.minichef"));
        migrator = new MiniChefMigratorTransfer(address(minichef), multisig);
    }

    function testMigrateTransfer(uint256 pid) public {
        vm.assume(pid < minichef.poolLength());

        IERC20 lpToken = IERC20(minichef.lpToken(pid));
        uint256 preBalance = lpToken.balanceOf(address(minichef));

        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        minichef.migrate(pid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(lpToken.balanceOf(multisig), preBalance);
        assertEq(lpToken.balanceOf(address(minichef)), 0);
    }
}
