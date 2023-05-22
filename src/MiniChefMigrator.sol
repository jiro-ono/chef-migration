// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "interfaces/IUniSwapV2Pair.sol";

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

    constructor(address _minichef) {
        minichef = _minichef;
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
        lpToken.transferFrom(minichef, address(lpToken), totalLiquidity);
        (uint amount0, uint amount1) = lpToken.burn(0x7812BCD0c0De8D15Ff4C47391d2d9AE1B4DE13f0);
        console2.log("amount0: %s", amount0);
        console2.log("amount1: %s", amount1);

        return dummyPair;
    }

    function createDummyPair(uint256 balance) private returns (DummyPair) {
        DummyPair dummyPair = new DummyPair(balance, minichef);
        return dummyPair;
    }
}