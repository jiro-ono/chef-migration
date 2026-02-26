// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "/MasterChefMigratorReceipt.sol";

/// @dev Minimal ERC20 mock with mint, transfer, transferFrom, approve, balanceOf, symbol
contract MockERC20WithSymbol {
    string public symbol;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _symbol) {
        symbol = _symbol;
    }

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

/// @dev ERC20 mock without symbol() to test fallback naming
contract MockERC20NoSymbol {
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

/// @dev Replicates MasterChef's migrate + deposit/withdraw/emergencyWithdraw logic
contract MockMasterChef {
    MasterChefMigratorReceipt public migrator;

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accSushiPerShare;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    function setMigrator(MasterChefMigratorReceipt _migrator) external {
        migrator = _migrator;
    }

    function addPool(IERC20 _lpToken) external returns (uint256 pid) {
        pid = poolInfo.length;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: 100,
            lastRewardBlock: block.number,
            accSushiPerShare: 0
        }));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function deposit(uint256 pid, uint256 amount) external {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        if (amount > 0) {
            pool.lpToken.transferFrom(msg.sender, address(this), amount);
            user.amount += amount;
        }
    }

    /// @dev Mirrors MasterChef.withdraw — calls pool.lpToken.safeTransfer(msg.sender, amount)
    /// We use transfer() here which is equivalent for testing purposes
    function withdraw(uint256 pid, uint256 amount) external {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, "withdraw: not good");
        user.amount -= amount;
        pool.lpToken.transfer(msg.sender, amount);
    }

    /// @dev Mirrors MasterChef.emergencyWithdraw
    function emergencyWithdraw(uint256 pid) external {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.transfer(msg.sender, amount);
    }

    /// @dev Mirrors MasterChef.migrate — approves migrator, calls migrate, checks balance invariant
    function migrate(uint256 pid) external {
        PoolInfo storage pool = poolInfo[pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }
}

contract MasterChefMigratorReceiptUnitTest is Test {
    event Migrated(address indexed lpToken, address indexed receiptToken, address indexed recipient, uint256 amount);
    event ReceiptDeployed(address indexed lpToken, address indexed receiptToken, string name, string symbol);

    MasterChefMigratorReceipt public migrator;
    MockMasterChef public mockChef;
    MockERC20WithSymbol public mockLP;
    address public operator;
    address public recipient = address(0xBEEF);
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        operator = tx.origin; // tests run as tx.origin by default
        mockChef = new MockMasterChef();
        migrator = new MasterChefMigratorReceipt(address(mockChef), operator, recipient);
        mockChef.setMigrator(migrator);

        mockLP = new MockERC20WithSymbol("SLP");
    }

    // --- Constructor tests ---

    function testConstructorSetsImmutables() public {
        assertEq(migrator.masterchef(), address(mockChef));
        assertEq(migrator.operator(), operator);
        assertEq(migrator.recipient(), recipient);
    }

    function testConstructorRevertsOnZeroOperator() public {
        vm.expectRevert("zero operator");
        new MasterChefMigratorReceipt(address(mockChef), address(0), recipient);
    }

    function testConstructorRevertsOnZeroRecipient() public {
        vm.expectRevert("zero recipient");
        new MasterChefMigratorReceipt(address(mockChef), operator, address(0));
    }

    // --- Access control ---

    function testMigrateRevertsWhenCallerIsNotMasterchef() public {
        vm.expectRevert("only masterchef");
        migrator.migrate(IERC20(address(mockLP)));
    }

    function testMigrateRevertsWhenOriginIsNotOperator() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        // Prank both msg.sender and tx.origin to a non-operator address
        vm.prank(address(mockChef), alice);
        vm.expectRevert("only operator");
        migrator.migrate(IERC20(address(mockLP)));
    }

    function testReceiptTokenOnlyMinterCanMint() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));
        mockChef.migrate(0);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));
        vm.expectRevert("only minter");
        receipt.mint(address(this), 100);
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

    function testMigrateReturnsReceiptWithCorrectBalance() public {
        uint256 amount = 500 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        // After migration, lpToken should be the receipt token
        (IERC20 newLp,,,) = mockChef.poolInfo(0);
        assertEq(newLp.balanceOf(address(mockChef)), amount);
        assertEq(newLp.balanceOf(address(0x1234)), 0);
    }

    function testMigrateRecordsMigration() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        address receiptAddr = migrator.migrated(address(mockLP));
        assertTrue(receiptAddr != address(0));
        (IERC20 newLp,,,) = mockChef.poolInfo(0);
        assertEq(receiptAddr, address(newLp));
    }

    function testMigrateEmitsEvents() public {
        uint256 amount = 100 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        // We can't predict receipt address for expectEmit on Migrated, but we can check ReceiptDeployed
        vm.recordLogs();
        mockChef.migrate(0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Should have ReceiptDeployed and Migrated events (plus Transfer/Approval from ERC20)
        bool foundMigrated = false;
        bool foundDeployed = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Migrated(address,address,address,uint256)")) {
                foundMigrated = true;
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(address(mockLP)))));
            }
            if (logs[i].topics[0] == keccak256("ReceiptDeployed(address,address,string,string)")) {
                foundDeployed = true;
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(address(mockLP)))));
            }
        }
        assertTrue(foundMigrated, "Migrated event not found");
        assertTrue(foundDeployed, "ReceiptDeployed event not found");
    }

    // --- Double-migrate guard ---

    function testDoubleMigrateReverts() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        // Add same LP to a second pool so we can attempt double migrate
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        // Direct call from masterchef context to test the guard
        vm.prank(address(mockChef));
        vm.expectRevert("already migrated");
        migrator.migrate(IERC20(address(mockLP)));
    }

    // --- Zero balance ---

    function testZeroBalanceReverts() public {
        mockChef.addPool(IERC20(address(mockLP)));

        vm.prank(address(mockChef));
        vm.expectRevert("zero balance");
        migrator.migrate(IERC20(address(mockLP)));
    }

    // --- Multiple pools ---

    function testMigrateMultiplePools() public {
        MockERC20WithSymbol lp1 = new MockERC20WithSymbol("LP1");
        MockERC20WithSymbol lp2 = new MockERC20WithSymbol("LP2");
        MockERC20WithSymbol lp3 = new MockERC20WithSymbol("LP3");

        lp1.mint(address(mockChef), 100 ether);
        lp2.mint(address(mockChef), 200 ether);
        lp3.mint(address(mockChef), 300 ether);

        mockChef.addPool(IERC20(address(lp1)));
        mockChef.addPool(IERC20(address(lp2)));
        mockChef.addPool(IERC20(address(lp3)));

        mockChef.migrate(0);
        mockChef.migrate(1);
        mockChef.migrate(2);

        // LP tokens sent to recipient
        assertEq(lp1.balanceOf(recipient), 100 ether);
        assertEq(lp2.balanceOf(recipient), 200 ether);
        assertEq(lp3.balanceOf(recipient), 300 ether);

        // Each pool has its own receipt token
        address r1 = migrator.migrated(address(lp1));
        address r2 = migrator.migrated(address(lp2));
        address r3 = migrator.migrated(address(lp3));
        assertTrue(r1 != r2 && r2 != r3 && r1 != r3);

        // Receipt balances correct
        (IERC20 newLp0,,,) = mockChef.poolInfo(0);
        (IERC20 newLp1,,,) = mockChef.poolInfo(1);
        (IERC20 newLp2,,,) = mockChef.poolInfo(2);
        assertEq(newLp0.balanceOf(address(mockChef)), 100 ether);
        assertEq(newLp1.balanceOf(address(mockChef)), 200 ether);
        assertEq(newLp2.balanceOf(address(mockChef)), 300 ether);
    }

    // --- Withdraw after migrate ---

    function testWithdrawAfterMigrate() public {
        uint256 amount = 1000 ether;
        mockLP.mint(alice, amount);
        mockChef.addPool(IERC20(address(mockLP)));

        // Alice deposits
        vm.startPrank(alice);
        mockLP.approve(address(mockChef), amount);
        mockChef.deposit(0, amount);
        vm.stopPrank();

        // Migrate
        mockChef.migrate(0);

        // Alice withdraws — should receive receipt tokens, not revert
        vm.prank(alice);
        mockChef.withdraw(0, amount);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);
        assertEq(receiptToken.balanceOf(alice), amount);
        assertEq(receiptToken.balanceOf(address(mockChef)), 0);
    }

    function testEmergencyWithdrawAfterMigrate() public {
        uint256 amount = 500 ether;
        mockLP.mint(alice, amount);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), amount);
        mockChef.deposit(0, amount);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.emergencyWithdraw(0);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);
        assertEq(receiptToken.balanceOf(alice), amount);
    }

    function testPartialWithdrawAfterMigrate() public {
        uint256 amount = 1000 ether;
        mockLP.mint(alice, amount);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), amount);
        mockChef.deposit(0, amount);
        vm.stopPrank();

        mockChef.migrate(0);

        // Partial withdraw
        vm.prank(alice);
        mockChef.withdraw(0, 400 ether);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);
        assertEq(receiptToken.balanceOf(alice), 400 ether);
        assertEq(receiptToken.balanceOf(address(mockChef)), 600 ether);

        // Withdraw remaining
        vm.prank(alice);
        mockChef.withdraw(0, 600 ether);

        assertEq(receiptToken.balanceOf(alice), 1000 ether);
        assertEq(receiptToken.balanceOf(address(mockChef)), 0);
    }

    // --- Receipt token ERC20 behavior ---

    function testReceiptTokenTransfer() public {
        mockLP.mint(alice, 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), 100 ether);
        mockChef.deposit(0, 100 ether);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.withdraw(0, 100 ether);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);

        // Alice transfers to bob
        vm.prank(alice);
        receiptToken.transfer(bob, 50 ether);

        assertEq(receiptToken.balanceOf(alice), 50 ether);
        assertEq(receiptToken.balanceOf(bob), 50 ether);
    }

    function testReceiptTokenApproveAndTransferFrom() public {
        mockLP.mint(alice, 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), 100 ether);
        mockChef.deposit(0, 100 ether);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.withdraw(0, 100 ether);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);

        // Alice approves bob
        vm.prank(alice);
        receiptToken.approve(bob, 30 ether);

        // Bob transfers from alice
        vm.prank(bob);
        IERC20(address(receiptToken)).transferFrom(alice, bob, 30 ether);

        assertEq(receiptToken.balanceOf(alice), 70 ether);
        assertEq(receiptToken.balanceOf(bob), 30 ether);
    }

    function testReceiptTokenBurn() public {
        mockLP.mint(alice, 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), 100 ether);
        mockChef.deposit(0, 100 ether);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.withdraw(0, 100 ether);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));

        vm.prank(alice);
        receipt.burn(40 ether);
        assertEq(receipt.balanceOf(alice), 60 ether);
        assertEq(receipt.totalSupply(), 60 ether);
    }

    function testReceiptTokenBurnFrom() public {
        mockLP.mint(alice, 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), 100 ether);
        mockChef.deposit(0, 100 ether);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.withdraw(0, 100 ether);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));

        vm.prank(alice);
        receipt.approve(bob, 25 ether);

        vm.prank(bob);
        receipt.burnFrom(alice, 25 ether);
        assertEq(receipt.balanceOf(alice), 75 ether);
        assertEq(receipt.totalSupply(), 75 ether);
    }

    function testReceiptTokenTotalSupply() public {
        uint256 amount = 999 ether;
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));
        assertEq(receipt.totalSupply(), amount);
    }

    function testReceiptTokenDecimals() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));
        assertEq(receipt.decimals(), 18);
    }

    // --- Naming ---

    function testReceiptTokenNamingWithSymbol() public {
        mockLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(mockLP)));
        assertEq(receipt.name(), "Sushi MasterChef Receipt: SLP");
        assertEq(receipt.symbol(), "mcR-SLP");
    }

    function testReceiptTokenNamingFallback() public {
        MockERC20NoSymbol noSymbolLP = new MockERC20NoSymbol();
        noSymbolLP.mint(address(mockChef), 100 ether);
        mockChef.addPool(IERC20(address(noSymbolLP)));

        mockChef.migrate(0);

        MasterChefReceiptToken receipt = MasterChefReceiptToken(migrator.migrated(address(noSymbolLP)));
        assertEq(receipt.name(), "Sushi MasterChef Receipt");
        assertEq(receipt.symbol(), "mcRECEIPT");
    }

    // --- Fuzz tests ---

    function testFuzzMigrateBalance(uint256 amount) public {
        vm.assume(amount > 0);
        mockLP.mint(address(mockChef), amount);
        mockChef.addPool(IERC20(address(mockLP)));

        mockChef.migrate(0);

        assertEq(mockLP.balanceOf(recipient), amount);
        (IERC20 newLp,,,) = mockChef.poolInfo(0);
        assertEq(newLp.balanceOf(address(mockChef)), amount);
    }

    function testFuzzPartialWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);

        mockLP.mint(alice, depositAmount);
        mockChef.addPool(IERC20(address(mockLP)));

        vm.startPrank(alice);
        mockLP.approve(address(mockChef), depositAmount);
        mockChef.deposit(0, depositAmount);
        vm.stopPrank();

        mockChef.migrate(0);

        vm.prank(alice);
        mockChef.withdraw(0, withdrawAmount);

        (IERC20 receiptToken,,,) = mockChef.poolInfo(0);
        assertEq(receiptToken.balanceOf(alice), withdrawAmount);
        assertEq(receiptToken.balanceOf(address(mockChef)), depositAmount - withdrawAmount);
    }
}
