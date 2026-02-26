// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "utils/BaseTest.sol";
import "interfaces/IMiniChefV2.sol";
import "/MiniChefMigratorTransfer.sol";

contract MigratorTransferTest is BaseTest {
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient);

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

    function testMigrateTransferEmitsEvent() public {
        uint256 pid = 0;
        IERC20 lpToken = IERC20(minichef.lpToken(pid));
        uint256 preBalance = lpToken.balanceOf(address(minichef));

        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));

        vm.expectEmit(true, true, false, true, address(migrator));
        emit Migration(address(lpToken), preBalance, multisig);

        minichef.migrate(pid);
        vm.stopPrank();
    }

    function testMigrateTransferNewLpTokenIsDummy() public {
        uint256 pid = 0;
        IERC20 lpToken = IERC20(minichef.lpToken(pid));
        uint256 preBalance = lpToken.balanceOf(address(minichef));

        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        minichef.migrate(pid);
        vm.stopPrank();

        // After migration, lpToken(pid) should be a DummyToken
        IERC20 newLp = IERC20(minichef.lpToken(pid));
        assertTrue(address(newLp) != address(lpToken));
        assertEq(newLp.balanceOf(address(minichef)), preBalance);
    }

    function testMigrateTransferOnlyMinichefCanCall() public {
        IERC20 lpToken = IERC20(minichef.lpToken(0));

        vm.expectRevert("only minichef");
        migrator.migrate(lpToken);
    }

    function testMigrateSequentialPids() public {
        uint256 pid0 = 0;
        uint256 pid1 = 1;

        IERC20 lp0 = IERC20(minichef.lpToken(pid0));
        IERC20 lp1 = IERC20(minichef.lpToken(pid1));
        uint256 preBal0 = lp0.balanceOf(address(minichef));
        uint256 preBal1 = lp1.balanceOf(address(minichef));

        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));

        minichef.migrate(pid0);

        // First pool migrated
        assertEq(lp0.balanceOf(multisig), preBal0);
        assertEq(lp0.balanceOf(address(minichef)), 0);

        // Second pool still untouched
        assertEq(lp1.balanceOf(address(minichef)), preBal1);

        minichef.migrate(pid1);

        // Second pool now migrated
        assertEq(lp1.balanceOf(multisig), preBal1);
        assertEq(lp1.balanceOf(address(minichef)), 0);

        // Both replaced with DummyTokens
        IERC20 newLp0 = IERC20(minichef.lpToken(pid0));
        IERC20 newLp1 = IERC20(minichef.lpToken(pid1));
        assertTrue(address(newLp0) != address(lp0));
        assertTrue(address(newLp1) != address(lp1));
        assertEq(newLp0.balanceOf(address(minichef)), preBal0);
        assertEq(newLp1.balanceOf(address(minichef)), preBal1);

        vm.stopPrank();
    }

    function testDoubleMigrationReverts() public {
        uint256 pid = 0;

        vm.startPrank(minichef.owner());
        minichef.setMigrator(address(migrator));
        minichef.migrate(pid);

        // Second migration on same pid should revert - DummyToken has no transferFrom
        vm.expectRevert();
        minichef.migrate(pid);
        vm.stopPrank();
    }
}
