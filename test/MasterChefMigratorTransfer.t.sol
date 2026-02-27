// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChef.sol";
import "/MasterChefMigratorTransfer.sol";

// Pin fork block for deterministic CI behavior.
// Block chosen because MasterChef pool + LP state is valid and stable here.
uint256 constant FORK_BLOCK = 24_551_130;

contract MasterChefMigratorTransferTest is BaseTest {
    IMasterChef public masterchef;
    MasterChefMigratorTransfer public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig

    uint256 public activePid;
    IERC20 public activeLpToken;
    uint256 public activePreBalance;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), FORK_BLOCK);
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

    }

    function testMigrateIdempotentOnSameLp() public {
        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(activePid);
        vm.stopPrank();

        // Direct call with same LP (balance is now 0) — should NOT revert
        vm.prank(address(masterchef));
        IERC20 dummy = migrator.migrate(activeLpToken);

        // Dummy reports 0 balance (no tokens left to sweep)
        assertEq(dummy.balanceOf(address(masterchef)), 0);
        // Recipient balance unchanged from first migration
        assertGt(activeLpToken.balanceOf(multisig), 0);
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
