// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title MasterChefV2DummyToken
/// @notice A minimal ERC20 that reports a fixed balance for a single holder
/// @dev Used to satisfy MasterChefV2's balance check after migration. MasterChefV2 requires
/// that the new LP token's balance equals the old LP token's balance. This dummy
/// token is deployed during migration and reports the expected balance to pass
/// that check, while the real LP tokens are transferred to the recipient.
contract MasterChefV2DummyToken {
    /// @notice Balance mapping - only the holder specified in constructor will have a balance
    mapping(address => uint256) private _balances;

    /// @notice Creates a dummy token with a predetermined balance for a specific holder
    /// @param balance The balance to report for the holder
    /// @param holder The address that will hold the balance (should be the MasterChefV2 contract)
    constructor(uint256 balance, address holder) {
        _balances[holder] = balance;
    }

    /// @notice Returns the balance of the specified account
    /// @param account The address to query
    /// @return The balance of the account
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}

/// @title MasterChefV2MigratorTransfer
/// @author Sushi
/// @notice Migrator contract that transfers LP tokens to a multisig instead of performing V2->V3 migration
/// @dev This contract is designed to be set as the migrator on the MasterChefV2 contract on Ethereum
/// mainnet. When MasterChefV2 calls the migrate function, instead of converting LP tokens to a new format,
/// this contract simply transfers all LP tokens to a designated recipient (e.g., a multisig wallet).
///
/// MasterChefV2 is the "double rewards" contract that sits on top of MasterChef V1, distributing
/// additional SUSHI rewards to specific pools.
///
/// Flow:
/// 1. Owner calls MasterChefV2.setMigrator(address(this))
/// 2. Anyone calls MasterChefV2.migrate(pid) for each pool
/// 3. MasterChefV2 approves this contract for LP tokens and calls migrate()
/// 4. This contract transfers LP tokens to recipient and returns a DummyToken
/// 5. MasterChefV2 stores the DummyToken as the new LP token (pool is effectively closed)
///
/// Security considerations:
/// - Only MasterChefV2 can call migrate() due to the sender check
/// - LP tokens are transferred directly to the immutable recipient address
/// - The pool becomes non-functional after migration (DummyToken has no real liquidity)
/// - Users should withdraw their LP tokens before migration or they will be locked
contract MasterChefV2MigratorTransfer {
    /// @notice The MasterChefV2 contract that is allowed to call migrate
    address public immutable masterchefv2;

    /// @notice The recipient address that will receive all migrated LP tokens
    address public immutable recipient;

    /// @notice Emitted when LP tokens are migrated to the recipient
    /// @param lpToken The address of the LP token that was migrated
    /// @param amount The amount of LP tokens transferred
    /// @param recipient The address that received the LP tokens
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient);

    /// @notice Initializes the migrator with the MasterChefV2 and recipient addresses
    /// @param _masterchefv2 The MasterChefV2 contract address that will call migrate
    /// @param _recipient The address that will receive all LP tokens (e.g., multisig)
    constructor(address _masterchefv2, address _recipient) {
        masterchefv2 = _masterchefv2;
        recipient = _recipient;
    }

    /// @notice Migrates LP tokens by transferring them to the recipient
    /// @dev Called by MasterChefV2 during the migration process. MasterChefV2 will have already
    /// approved this contract to spend its LP tokens before calling this function.
    /// @param lpToken The LP token to migrate
    /// @return A DummyToken that reports the same balance to satisfy MasterChefV2's balance check
    function migrate(IERC20 lpToken) external returns (IERC20) {
        require(msg.sender == masterchefv2, "only masterchefv2");

        uint256 balance = lpToken.balanceOf(masterchefv2);
        lpToken.transferFrom(masterchefv2, recipient, balance);

        emit Migration(address(lpToken), balance, recipient);

        // Deploy a dummy token that reports the expected balance to MasterChefV2
        // This satisfies the requirement: bal == newLpToken.balanceOf(address(this))
        MasterChefV2DummyToken dummy = new MasterChefV2DummyToken(balance, masterchefv2);
        return IERC20(address(dummy));
    }
}
