// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "/MiniChefMigratorTransfer.sol";

/// @dev Minimal ERC20 mock with mint, transfer, transferFrom, approve, balanceOf
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Replicates MiniChef's exact migrate logic with balance check
contract MockMiniChef {
    MiniChefMigratorTransfer public migrator;
    mapping(uint256 => IERC20) public lpToken;
    uint256 public poolCount;

    function setMigrator(MiniChefMigratorTransfer _migrator) external {
        migrator = _migrator;
    }

    function addPool(IERC20 _lpToken) external returns (uint256 pid) {
        pid = poolCount++;
        lpToken[pid] = _lpToken;
    }

    function migrate(uint256 pid) external {
        IERC20 _lpToken = lpToken[pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "balance mismatch");
        lpToken[pid] = newLpToken;
    }
}

contract MigratorTransferUnitTest is Test {
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient);

    MiniChefMigratorTransfer public migrator;
    MockMiniChef public mockChef;
    MockERC20 public mockLP;
    address public recipient = address(0xBEEF);

    function setUp() public {
        mockChef = new MockMiniChef();
        migrator = new MiniChefMigratorTransfer(address(mockChef), recipient);
        mockChef.setMigrator(migrator);

        mockLP = new MockERC20();
    }

    // --- Constructor tests ---

    function testConstructorSetsImmutables() public {
        assertEq(migrator.minichef(), address(mockChef));
        assertEq(migrator.recipient(), recipient);
    }

    function testConstructorRevertsOnZeroRecipient() public {
        vm.expectRevert("zero recipient");
        new MiniChefMigratorTransfer(address(mockChef), address(0));
    }

    // --- Access control ---

    function testMigrateRevertsWhenCallerIsNotMinichef() public {
        vm.expectRevert("only minichef");
        migrator.migrate(IERC20(address(mockLP)));
    }

    // --- Core migration logic ---

    function testMigrateTransfersFullBalance() public {
        uint256 amount = 1000 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), amount);
        assertEq(mockLP.balanceOf(address(mockChef)), 0);
    }

    function testMigrateReturnsDummyWithCorrectBalance() public {
        uint256 amount = 500 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        // After migration, lpToken[0] should be the DummyToken
        IERC20 newLp = mockChef.lpToken(0);
        assertEq(newLp.balanceOf(address(mockChef)), amount);
        assertEq(newLp.balanceOf(address(0x1234)), 0);
    }

    function testMigrateEmitsMigrationEvent() public {
        uint256 amount = 100 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        // The event is emitted by the migrator inside the mockChef.migrate() call
        // We check for the event on the migrator address
        vm.expectEmit(true, true, false, true, address(migrator));
        emit Migration(address(mockLP), amount, recipient);

        mockChef.migrate(0);
    }

    function testMigrateWithZeroBalance() public {
        // LP with 0 balance
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), 0);
        IERC20 newLp = mockChef.lpToken(0);
        assertEq(newLp.balanceOf(address(mockChef)), 0);
    }

    function testMigrateSatisfiesBalanceCheck() public {
        // This test verifies the full MockMiniChef flow including the
        // require(bal == newLpToken.balanceOf(address(this))) check.
        // If the balance check fails, mockChef.migrate() reverts.
        uint256 amount = 777 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        // Should not revert - balance check passes
        mockChef.migrate(0);

        // Verify post-state
        IERC20 newLp = mockChef.lpToken(0);
        assertEq(newLp.balanceOf(address(mockChef)), amount);
    }

    function testMigrateFuzzedBalance(uint256 amount) public {
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), amount);
        assertEq(mockLP.balanceOf(address(mockChef)), 0);

        IERC20 newLp = mockChef.lpToken(0);
        assertEq(newLp.balanceOf(address(mockChef)), amount);
    }

    function testMigrateMultiplePools() public {
        MockERC20 lp1 = new MockERC20();
        MockERC20 lp2 = new MockERC20();
        MockERC20 lp3 = new MockERC20();

        lp1.mint(address(mockChef), 100 ether);
        lp2.mint(address(mockChef), 200 ether);
        lp3.mint(address(mockChef), 300 ether);

        mockChef.addPool(IERC20(address(lp1)));
        mockChef.addPool(IERC20(address(lp2)));
        mockChef.addPool(IERC20(address(lp3)));

        mockChef.migrate(0);
        mockChef.migrate(1);
        mockChef.migrate(2);

        assertEq(lp1.balanceOf(recipient), 100 ether);
        assertEq(lp2.balanceOf(recipient), 200 ether);
        assertEq(lp3.balanceOf(recipient), 300 ether);

        assertEq(mockChef.lpToken(0).balanceOf(address(mockChef)), 100 ether);
        assertEq(mockChef.lpToken(1).balanceOf(address(mockChef)), 200 ether);
        assertEq(mockChef.lpToken(2).balanceOf(address(mockChef)), 300 ether);
    }

    // --- DummyToken tests ---

    function testDummyTokenBalanceOf() public {
        uint256 amount = 42 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        IERC20 dummy = mockChef.lpToken(0);
        // Holder (mockChef) gets correct balance
        assertEq(dummy.balanceOf(address(mockChef)), amount);
        // Non-holders get 0
        assertEq(dummy.balanceOf(address(this)), 0);
        assertEq(dummy.balanceOf(recipient), 0);
        assertEq(dummy.balanceOf(address(0)), 0);
    }
}
