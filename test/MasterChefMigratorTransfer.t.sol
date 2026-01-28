// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChef.sol";
import "/MasterChefMigratorTransfer.sol";

contract MasterChefMigratorTransferTest is BaseTest {
    IMasterChef public masterchef;
    MasterChefMigratorTransfer public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig

    function setUp() public override {
        forkMainnet();
        super.setUp();
        masterchef = IMasterChef(constants.getAddress("mainnet.masterchef"));
        migrator = new MasterChefMigratorTransfer(address(masterchef), multisig);
    }

    function testMigrateTransfer(uint256 pid) public {
        vm.assume(pid < masterchef.poolLength());

        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);
        uint256 preBalance = lpToken.balanceOf(address(masterchef));

        // Skip pools with zero balance
        vm.assume(preBalance > 0);

        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(lpToken.balanceOf(multisig), preBalance);
        assertEq(lpToken.balanceOf(address(masterchef)), 0);
    }
}
