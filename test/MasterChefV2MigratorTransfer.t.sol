// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChefV2.sol";
import "/MasterChefV2MigratorTransfer.sol";

// Pin fork block for deterministic CI behavior.
// Block chosen because MasterChef pool + LP state is valid and stable here.
uint256 constant FORK_BLOCK = 24_551_130;

contract MasterChefV2MigratorTransferTest is BaseTest {
    IMasterChefV2 public masterchefv2;
    MasterChefV2MigratorTransfer public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig

    uint256 public activePid;
    IERC20 public activeLpToken;
    uint256 public activePreBalance;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), FORK_BLOCK);
        super.setUp();
        masterchefv2 = IMasterChefV2(constants.getAddress("mainnet.masterchefv2"));
        migrator = new MasterChefV2MigratorTransfer(address(masterchefv2), multisig);

        // Dynamically find a pool with nonzero LP balance
        uint256 len = masterchefv2.poolLength();
        for (uint256 i = 0; i < len; i++) {
            IERC20 lp = masterchefv2.lpToken(i);
            uint256 bal = lp.balanceOf(address(masterchefv2));
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

        vm.startPrank(masterchefv2.owner());
        masterchefv2.setMigrator(address(migrator));
        masterchefv2.migrate(activePid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(activeLpToken.balanceOf(multisig), preMsigBalance + activePreBalance);
        assertEq(activeLpToken.balanceOf(address(masterchefv2)), 0);

        // Pool now points to dummy token
        IERC20 newLp = masterchefv2.lpToken(activePid);
        assertTrue(address(newLp) != address(activeLpToken));
        assertEq(newLp.balanceOf(address(masterchefv2)), activePreBalance);

    }

    function testMigrateIdempotentOnSameLp() public {
        vm.startPrank(masterchefv2.owner());
        masterchefv2.setMigrator(address(migrator));
        masterchefv2.migrate(activePid);
        vm.stopPrank();

        // Direct call with same LP (balance is now 0) — should NOT revert
        vm.prank(address(masterchefv2));
        IERC20 dummy = migrator.migrate(activeLpToken);

        // Dummy reports 0 balance (no tokens left to sweep)
        assertEq(dummy.balanceOf(address(masterchefv2)), 0);
        // Recipient balance unchanged from first migration
        assertGt(activeLpToken.balanceOf(multisig), 0);
    }

    function testMigrateEmitsFullEvent() public {
        vm.startPrank(masterchefv2.owner());
        masterchefv2.setMigrator(address(migrator));

        vm.recordLogs();
        masterchefv2.migrate(activePid);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the Migration event
        bytes32 migrationSig = keccak256("Migration(address,uint256,address,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == migrationSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(activeLpToken));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), multisig);
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
