// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "interfaces/IUniSwapV2Pair.sol";
import "interfaces/IV3Migrator.sol";

import {console2} from "forge-std/console2.sol";

contract DummyPair {
    mapping (address => uint256) private _balances;

    constructor(uint256 initialBalance, address minichef) {
        _balances[minichef] = initialBalance;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
}

contract MiniChefMigrator {
    address minichef;
    IV3Migrator v3Migrator;
    int24 maxTickLower = -887220;
    int24 maxTickUpper = 887220;

    mapping (uint256 => address[]) public usersForPid;

    struct MigrateParams {
        address pair; // the Uniswap v2-compatible pair
        uint256 liquidityToMigrate; // expected to be balanceOf(msg.sender)
        uint8 percentageToMigrate; // represented as a numerator over 100
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min; // must be discounted by percentageToMigrate
        uint256 amount1Min; // must be discounted by percentageToMigrate
        address recipient;
        uint256 deadline;
        bool refundAsETH;
    }

    constructor(address _minichef, address _v3Migrator) {
        minichef = _minichef;
        v3Migrator = IV3Migrator(_v3Migrator);
    }

    function addToPidMap(uint256 pid, address user) public {
        usersForPid[pid].push(user);
    }

    function addMultipleToPidMap(uint256 pid, address[] memory users) public {
        for (uint256 i = 0; i < users.length; i++) {
            usersForPid[pid].push(users[i]);
        }
    }

    function setEntirePidMap(uint256 pid, address[] memory users) public {
        usersForPid[pid] = users;
    }

    function getPidMap(uint256 pid) public view returns (address[] memory) {
        return usersForPid[pid];
    }

    function migrate(IUniswapV2Pair lpToken) public returns (DummyPair) {
        // add checks that call is coming from minichef
        // add checks operator is making the call
        require(msg.sender == minichef, "migrate not called from minichef");
        //require(tx.origin == operatorAddr, "call not made from operator");
        
        DummyPair dummyPair = createDummyPair(lpToken.balanceOf(minichef));
        console2.log("dummyPair: %s", address(dummyPair));
        
        // breakdown lp pair
        address token0 = lpToken.token0();
        address token1 = lpToken.token1();
        uint256 totalLiquidity = lpToken.balanceOf(msg.sender);

        // should have slippage detection during unwind here
        lpToken.transferFrom(minichef, address(this), totalLiquidity);
        //(uint amount0, uint amount1) = lpToken.burn(0x7812BCD0c0De8D15Ff4C47391d2d9AE1B4DE13f0);
        //console2.log("amount0: %s", amount0);
        //console2.log("amount1: %s", amount1);

        // migrate to full v3 position
        IV3Migrator.MigrateParams memory params = IV3Migrator.MigrateParams({
            pair: address(lpToken),
            liquidityToMigrate: totalLiquidity,
            percentageToMigrate: 100,
            token0: token0,
            token1: token1,
            fee: 500,
            tickLower: maxTickLower,
            tickUpper: maxTickUpper,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(0x7812BCD0c0De8D15Ff4C47391d2d9AE1B4DE13f0),
            deadline: block.timestamp + 1000000000,
            refundAsETH: false
        });

        lpToken.approve(address(v3Migrator), totalLiquidity);
        v3Migrator.migrate(
            params
        );

        console2.log("did the migration");

        return dummyPair;
    }

    function createDummyPair(uint256 balance) private returns (DummyPair) {
        DummyPair dummyPair = new DummyPair(balance, minichef);
        return dummyPair;
    }
}