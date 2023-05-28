// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

interface IUniswapV3Factory {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
     function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
    
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}