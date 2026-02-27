// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "/MasterChefV2MigratorTransfer.sol";

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

/// @dev Replicates MasterChefV2's exact migrate logic with lpToken mapping + balance check
contract MockMasterChefV2 {
    MasterChefV2MigratorTransfer public migrator;
    mapping(uint256 => IERC20) public lpToken;
    uint256 public poolCount;

    function setMigrator(MasterChefV2MigratorTransfer _migrator) external {
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

    function withdraw(uint256 pid, uint256 amount) external {
        IERC20 _lpToken = lpToken[pid];
        _lpToken.transfer(msg.sender, amount);
    }

    function emergencyWithdraw(uint256 pid) external {
        IERC20 _lpToken = lpToken[pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.transfer(msg.sender, bal);
    }
}

contract MasterChefV2MigratorTransferUnitTest is Test {
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient, address dummyToken, uint256 blockNumber);

    MasterChefV2MigratorTransfer public migrator;
    MockMasterChefV2 public mockChef;
    MockERC20 public mockLP;
    address public recipient = address(0xBEEF);

    function setUp() public {
        mockChef = new MockMasterChefV2();
        migrator = new MasterChefV2MigratorTransfer(address(mockChef), recipient);
        mockChef.setMigrator(migrator);

        mockLP = new MockERC20();
    }

    // --- Constructor tests ---

    function testConstructorSetsImmutables() public {
        assertEq(migrator.masterchefv2(), address(mockChef));
        assertEq(migrator.recipient(), recipient);
    }

    function testConstructorRevertsOnZeroMasterchefv2() public {
        vm.expectRevert("zero masterchefv2");
        new MasterChefV2MigratorTransfer(address(0), recipient);
    }

    function testConstructorRevertsOnZeroRecipient() public {
        vm.expectRevert("zero recipient");
        new MasterChefV2MigratorTransfer(address(mockChef), address(0));
    }

    // --- Access control ---

    function testMigrateRevertsWhenCallerIsNotMasterchefv2() public {
        vm.expectRevert("only masterchefv2");
        migrator.migrate(IERC20(address(mockLP)));
    }

    // --- Zero balance (idempotent) ---

    function testMigrateWithZeroBalance() public {
        mockChef.addPool(IERC20(address(mockLP)));

        // Zero balance succeeds — returns dummy(0), bricks the pool
        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), 0);
        IERC20 newLp = mockChef.lpToken(0);
        assertEq(newLp.balanceOf(address(mockChef)), 0);
    }

    // --- Duplicate LP across pids ---

    function testMigrateDuplicateLpAcrossPids() public {
        uint256 amount = 1000 ether;
        mockLP.mint(address(mockChef), amount);

        // Two pids referencing the same LP token
        mockChef.addPool(IERC20(address(mockLP))); // pid 0
        mockChef.addPool(IERC20(address(mockLP))); // pid 1

        vm.recordLogs();

        // First migration sweeps tokens
        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), amount);
        assertEq(mockLP.balanceOf(address(mockChef)), 0);
        IERC20 dummyA = mockChef.lpToken(0);
        assertEq(dummyA.balanceOf(address(mockChef)), amount);

        // Second migration: balance is 0, should NOT revert, still bricks pid 1
        mockChef.migrate(1);

        // Recipient balance unchanged
        assertEq(mockLP.balanceOf(recipient), amount);
        IERC20 dummyB = mockChef.lpToken(1);
        assertEq(dummyB.balanceOf(address(mockChef)), 0);

        // Both pids point to different dummy tokens
        assertTrue(address(dummyA) != address(dummyB));
        assertTrue(address(dummyA) != address(mockLP));
        assertTrue(address(dummyB) != address(mockLP));

        // Verify events: first amount == initial balance, second amount == 0
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 migrationSig = keccak256("Migration(address,uint256,address,address,uint256)");
        uint256 eventCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == migrationSig) {
                (uint256 emittedAmount,,) = abi.decode(logs[i].data, (uint256, address, uint256));
                if (eventCount == 0) {
                    assertEq(emittedAmount, amount);
                } else {
                    assertEq(emittedAmount, 0);
                }
                eventCount++;
            }
        }
        assertEq(eventCount, 2);
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

    function testMigrateSatisfiesBalanceCheck() public {
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

    // --- Event tests ---

    function testMigrateEmitsEventWithDummyAndBlock() public {
        uint256 amount = 100 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.recordLogs();
        mockChef.migrate(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 migrationSig = keccak256("Migration(address,uint256,address,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == migrationSig) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(mockLP));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), recipient);
                (uint256 emittedAmount, address dummyToken, uint256 blockNumber) = abi.decode(logs[i].data, (uint256, address, uint256));
                assertEq(emittedAmount, amount);
                assertTrue(dummyToken != address(0));
                assertEq(blockNumber, block.number);
                break;
            }
        }
        assertTrue(found, "Migration event not found");
    }

    // --- Bricking tests ---

    function testWithdrawRevertsAfterMigration() public {
        uint256 amount = 1000 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        // withdraw calls dummy.transfer which doesn't exist → revert
        vm.expectRevert();
        mockChef.withdraw(0, amount);
    }

    function testEmergencyWithdrawRevertsAfterMigration() public {
        uint256 amount = 1000 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        // emergencyWithdraw calls dummy.transfer which doesn't exist → revert
        vm.expectRevert();
        mockChef.emergencyWithdraw(0);
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
