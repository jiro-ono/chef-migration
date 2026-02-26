// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMasterChef.sol";
import "/MasterChefMigratorReceipt.sol";

contract MasterChefMigratorReceiptTest is BaseTest {
    IMasterChef public masterchef;
    MasterChefMigratorReceipt public migrator;
    address public multisig = 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7; // Sushi Ops multisig
    address public operator;

    function setUp() public override {
        forkMainnet();
        super.setUp();
        operator = tx.origin;
        masterchef = IMasterChef(constants.getAddress("mainnet.masterchef"));
        migrator = new MasterChefMigratorReceipt(address(masterchef), operator, multisig);
    }

    function testMigrateTransfer(uint256 pid) public {
        vm.assume(pid < masterchef.poolLength());

        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);
        uint256 preBalance = lpToken.balanceOf(address(masterchef));

        // Skip pools with zero balance
        vm.assume(preBalance > 0);

        // Skip non-standard LP tokens whose allowance() reverts
        // (MasterChef.migrate calls safeApprove which checks allowance)
        try lpToken.allowance(address(masterchef), address(this)) {} catch {
            vm.assume(false);
        }

        uint256 multisigPreBalance = lpToken.balanceOf(multisig);

        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        // LP tokens transferred to multisig
        assertEq(lpToken.balanceOf(multisig), multisigPreBalance + preBalance);
        assertEq(lpToken.balanceOf(address(masterchef)), 0);

        // Receipt token recorded
        address receiptAddr = migrator.migrated(address(lpToken));
        assertTrue(receiptAddr != address(0));
    }

    function testWithdrawAfterMigrate() public {
        uint256 pid = 0;
        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);

        // Give alice LP tokens and deposit into MasterChef
        uint256 amount = 10 ether;
        deal(address(lpToken), alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(masterchef), amount);
        masterchef.deposit(pid, amount);
        vm.stopPrank();

        // Verify alice deposited
        (uint256 userAmount,) = masterchef.userInfo(pid, alice);
        assertEq(userAmount, amount);

        // Migrate
        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        // Alice withdraws — should get receipt tokens, not revert
        vm.prank(alice);
        masterchef.withdraw(pid, amount);

        // Alice holds receipt tokens
        address receiptAddr = migrator.migrated(address(lpToken));
        assertEq(IERC20(receiptAddr).balanceOf(alice), amount);
    }

    function testEmergencyWithdrawAfterMigrate() public {
        uint256 pid = 0;
        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);

        uint256 amount = 10 ether;
        deal(address(lpToken), alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(masterchef), amount);
        masterchef.deposit(pid, amount);
        vm.stopPrank();

        // Migrate
        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        // Alice emergency withdraws
        vm.prank(alice);
        masterchef.emergencyWithdraw(pid);

        address receiptAddr = migrator.migrated(address(lpToken));
        assertEq(IERC20(receiptAddr).balanceOf(alice), amount);
    }

    function testReceiptTokenNaming() public {
        uint256 pid = 0;
        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);

        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(lpToken)));
        // Should have the LP token's symbol in the name
        string memory sym = IERC20Metadata(address(lpToken)).symbol();
        assertEq(receipt.name(), string.concat("Sushi MasterChef Receipt: ", sym));
        assertEq(receipt.symbol(), string.concat("mcR-", sym));
    }

    function testReceiptTokenTransferable() public {
        uint256 pid = 0;
        (IERC20 lpToken,,,) = masterchef.poolInfo(pid);

        uint256 amount = 10 ether;
        deal(address(lpToken), alice, amount);

        vm.startPrank(alice);
        lpToken.approve(address(masterchef), amount);
        masterchef.deposit(pid, amount);
        vm.stopPrank();

        vm.startPrank(masterchef.owner());
        masterchef.setMigrator(address(migrator));
        masterchef.migrate(pid);
        vm.stopPrank();

        vm.prank(alice);
        masterchef.withdraw(pid, amount);

        IERC20 receiptToken = IERC20(migrator.migrated(address(lpToken)));

        // Alice transfers receipt tokens to bob
        vm.prank(alice);
        receiptToken.transfer(bob, amount);

        assertEq(receiptToken.balanceOf(alice), 0);
        assertEq(receiptToken.balanceOf(bob), amount);
    }
}
