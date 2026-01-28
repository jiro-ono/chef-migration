// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChefV2.sol";
import "/MasterChefV2MigratorTransfer.sol";

contract MasterChefV2MigratorTransferTest is BaseTest {
    IMasterChefV2 public masterchefv2;
    MasterChefV2MigratorTransfer public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig

    function setUp() public override {
        forkMainnet();
        super.setUp();
        masterchefv2 = IMasterChefV2(constants.getAddress("mainnet.masterchefv2"));
        migrator = new MasterChefV2MigratorTransfer(address(masterchefv2), multisig);
    }

    function testMigrateTransfer(uint256 pid) public {
        vm.assume(pid < masterchefv2.poolLength());

        IERC20 lpToken = masterchefv2.lpToken(pid);
        uint256 preBalance = lpToken.balanceOf(address(masterchefv2));

        // Skip pools with zero balance
        vm.assume(preBalance > 0);

        vm.startPrank(masterchefv2.owner());
        masterchefv2.setMigrator(address(migrator));
        masterchefv2.migrate(pid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(lpToken.balanceOf(multisig), preBalance);
        assertEq(lpToken.balanceOf(address(masterchefv2)), 0);
    }
}
