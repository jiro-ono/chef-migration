// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "interfaces/IUniSwapV2Pair.sol";

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
    address miniChef;

    constructor(address _miniChef) {
        miniChef = _miniChef;
    }

    function migrate(IUniswapV2Pair _lpToken) public returns (address) {
        DummyPair dummyPair = createDummyPair(_lpToken.balanceOf(miniChef));

    }

    function createDummyPair(uint256 balance) private returns (DummyPair) {
        DummyPair dummyPair = new DummyPair(balance, miniChef);
        return dummyPair
    }
}