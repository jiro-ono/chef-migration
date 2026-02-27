// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChef.sol";
import "/MasterChefMigratorTransfer.sol";

contract MasterChefMigratorTransferTest is BaseTest {
    IMasterChef public masterchef;
    MasterChefMigratorTransfer public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig

    uint256 public activePid;
    IERC20 public activeLpToken;
    uint256 public activePreBalance;

    function setUp() public override {
        forkMainnet();
        super.setUp();
        masterchef = IMasterChef(constants.getAddress("mainnet.masterchef"));
        migrator = new MasterChefMigratorTransfer(address(masterchef), multisig);

        // Dynamically find a pool with nonzero LP balance
        uint256 len = masterchef.poolLength();
        for (uint256 i = 0; i < len; i++) {
            (IERC20 lp,,,) = masterchef.poolInfo(i);
            uint256 bal = lp.balanceOf(address(masterchef));
            if (bal > 0) {
                activePid = i;
                activeLpToken = lp;
                activePreBalance = bal;
                break;
            }
        }
        require(activePreBalance > 0, "no active pool found");
    }

    function testMigrateSweepsBalanceAndSetsDummy() public {
        uint256 preMsigBalance = activeLpToken.balanceOf(multisig);

        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(activePid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(activeLpToken.balanceOf(multisig), preMsigBalance + activePreBalance);
        assertEq(activeLpToken.balanceOf(address(masterchef)), 0);

        // Pool now points to dummy token
        (IERC20 newLp,,,) = masterchef.poolInfo(activePid);
        assertTrue(address(newLp) != address(activeLpToken));
        assertEq(newLp.balanceOf(address(masterchef)), activePreBalance);

        // migratedLp flag set
        assertTrue(migrator.migratedLp(address(activeLpToken)));
    }

    function testMigrateRevertsOnSecondCall() public {
        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(activePid);

        // Second call should revert - the LP token has already been migrated
        // Need a fresh migrator set since poolInfo now points to dummy
        // But the migratedLp guard is on the original LP token address,
        // and migrate() is called with the new dummy token which hasn't been migrated.
        // To test the guard properly, we need a second pool with the same LP token,
        // or we test via direct call.
        vm.stopPrank();

        // Direct call: prank as masterchef and call migrate with the same LP token
        vm.prank(address(masterchef));
        vm.expectRevert("already migrated");
        migrator.migrate(activeLpToken);
    }

    function testMigrateRevertsOnZeroBalance() public {
        // Find a pool with zero balance, or use pid 0 after migrating it
        uint256 len = masterchef.poolLength();
        uint256 zeroPid = type(uint256).max;
        IERC20 zeroLp;
        for (uint256 i = 0; i < len; i++) {
            (IERC20 lp,,,) = masterchef.poolInfo(i);
            uint256 bal = lp.balanceOf(address(masterchef));
            if (bal == 0) {
                zeroPid = i;
                zeroLp = lp;
                break;
            }
        }

        if (zeroPid != type(uint256).max) {
            // Direct call with zero-balance LP token
            vm.prank(address(masterchef));
            vm.expectRevert("nothing to migrate");
            migrator.migrate(zeroLp);
        } else {
            // All pools have balance — create a dummy address as LP token with zero balance
            vm.prank(address(masterchef));
            vm.expectRevert(); // will revert (either nothing to migrate or call failure)
            migrator.migrate(IERC20(address(0xDEAD)));
        }
    }

    function testMigrateEmitsFullEvent() public {
        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));

        vm.recordLogs();
        masterchef.migrate(activePid);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the Migration event
        bytes32 migrationSig = keccak256("Migration(address,uint256,address,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == migrationSig) {
                found = true;
                // topics[1] = indexed lpToken
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(activeLpToken));
                // topics[2] = indexed recipient
                assertEq(address(uint160(uint256(logs[i].topics[2]))), multisig);
                // Decode non-indexed: amount, dummyToken, blockNumber
                (uint256 amount, address dummyToken, uint256 blockNumber) = abi.decode(logs[i].data, (uint256, address, uint256));
                assertEq(amount, activePreBalance);
                assertTrue(dummyToken != address(0));
                assertEq(blockNumber, block.number);
                break;
            }
        }
        assertTrue(found, "Migration event not found");
    }
}
