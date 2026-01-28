// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title MasterChefDummyToken
/// @notice A minimal ERC20 that reports a fixed balance for a single holder
/// @dev Used to satisfy MasterChef's balance check after migration. MasterChef requires
/// that the new LP token's balance equals the old LP token's balance. This dummy
/// token is deployed during migration and reports the expected balance to pass
/// that check, while the real LP tokens are transferred to the recipient.
contract MasterChefDummyToken {
    /// @notice Balance mapping - only the holder specified in constructor will have a balance
    mapping(address => uint256) private _balances;

    /// @notice Creates a dummy token with a predetermined balance for a specific holder
    /// @param balance The balance to report for the holder
    /// @param holder The address that will hold the balance (should be the MasterChef contract)
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

/// @title MasterChefMigratorTransfer
/// @author Sushi
/// @notice Migrator contract that transfers LP tokens to a multisig instead of performing V2->V3 migration
/// @dev This contract is designed to be set as the migrator on the MasterChef (V1) contract on Ethereum
/// mainnet. When MasterChef calls the migrate function, instead of converting LP tokens to a new format,
/// this contract simply transfers all LP tokens to a designated recipient (e.g., a multisig wallet).
///
/// Flow:
/// 1. Owner calls MasterChef.setMigrator(address(this))
/// 2. Anyone calls MasterChef.migrate(pid) for each pool
/// 3. MasterChef calls safeApprove for LP tokens and calls migrate()
/// 4. This contract transfers LP tokens to recipient and returns a DummyToken
/// 5. MasterChef stores the DummyToken as the new LP token (pool is effectively closed)
///
/// Security considerations:
/// - Only MasterChef can call migrate() due to the sender check
/// - LP tokens are transferred directly to the immutable recipient address
/// - The pool becomes non-functional after migration (DummyToken has no real liquidity)
/// - Users should withdraw their LP tokens before migration or they will be locked
contract MasterChefMigratorTransfer {
    /// @notice The MasterChef contract that is allowed to call migrate
    address public immutable masterchef;

    /// @notice The recipient address that will receive all migrated LP tokens
    address public immutable recipient;

    /// @notice Emitted when LP tokens are migrated to the recipient
    /// @param lpToken The address of the LP token that was migrated
    /// @param amount The amount of LP tokens transferred
    /// @param recipient The address that received the LP tokens
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient);

    /// @notice Initializes the migrator with the MasterChef and recipient addresses
    /// @param _masterchef The MasterChef contract address that will call migrate
    /// @param _recipient The address that will receive all LP tokens (e.g., multisig)
    constructor(address _masterchef, address _recipient) {
        masterchef = _masterchef;
        recipient = _recipient;
    }

    /// @notice Migrates LP tokens by transferring them to the recipient
    /// @dev Called by MasterChef during the migration process. MasterChef will have already
    /// called safeApprove for this contract to spend its LP tokens before calling this function.
    /// @param lpToken The LP token to migrate
    /// @return A DummyToken that reports the same balance to satisfy MasterChef's balance check
    function migrate(IERC20 lpToken) external returns (IERC20) {
        require(msg.sender == masterchef, "only masterchef");

        uint256 balance = lpToken.balanceOf(masterchef);
        lpToken.transferFrom(masterchef, recipient, balance);

        emit Migration(address(lpToken), balance, recipient);

        // Deploy a dummy token that reports the expected balance to MasterChef
        // This satisfies the requirement: bal == newLpToken.balanceOf(address(this))
        MasterChefDummyToken dummy = new MasterChefDummyToken(balance, masterchef);
        return IERC20(address(dummy));
    }
}
