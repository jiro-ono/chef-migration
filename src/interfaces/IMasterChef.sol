// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IMasterChef {
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 pid) external view returns (
        IERC20 lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accSushiPerShare
    );
    function owner() external view returns (address);
    function migrator() external view returns (address);
    function setMigrator(address _migrator) external;
    function migrate(uint256 _pid) external;
}
