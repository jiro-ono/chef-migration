// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @dev Local interface for transferFrom selector — keeps migrator self-contained
/// without expanding the shared IERC20 interface.
interface IERC20TransferFrom {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title MasterChefKillDummyToken
/// @notice A minimal ERC20 that reports a fixed balance for a single holder
/// @dev Intentionally has no transfer/approve functions, which bricks the pool —
/// any attempt by MasterChef to call withdraw or emergencyWithdraw will revert
/// because the dummy token cannot be transferred.
contract MasterChefKillDummyToken {
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
/// 4. This contract transfers LP tokens to recipient and returns a KillDummyToken
/// 5. MasterChef stores the KillDummyToken as the new LP token (pool is effectively bricked)
///
/// Security considerations:
/// - Only MasterChef can call migrate() due to the sender check
/// - LP tokens are transferred directly to the immutable recipient address
/// - Idempotent per LP token: first call sweeps balance, subsequent calls (e.g. duplicate
///   LP pids) sweep 0 and still brick the pool with a dummy token
/// - The pool becomes non-functional after migration (KillDummyToken has no transfer function)
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
    /// @param dummyToken The address of the kill dummy token deployed for this pool
    /// @param blockNumber The block number at which the migration occurred
    event Migration(address indexed lpToken, uint256 amount, address indexed recipient, address dummyToken, uint256 blockNumber);

    /// @notice Initializes the migrator with the MasterChef and recipient addresses
    /// @param _masterchef The MasterChef contract address that will call migrate
    /// @param _recipient The address that will receive all LP tokens (e.g., multisig)
    constructor(address _masterchef, address _recipient) {
        require(_masterchef != address(0), "zero masterchef");
        require(_recipient != address(0), "zero recipient");
        masterchef = _masterchef;
        recipient = _recipient;
    }

    /// @notice Migrates LP tokens by transferring them to the recipient
    /// @dev Called by MasterChef during the migration process. MasterChef will have already
    /// called safeApprove for this contract to spend its LP tokens before calling this function.
    /// @param lpToken The LP token to migrate
    /// @return A KillDummyToken that reports the same balance to satisfy MasterChef's balance check
    function migrate(IERC20 lpToken) external returns (IERC20) {
        require(msg.sender == masterchef, "only masterchef");

        uint256 balance = lpToken.balanceOf(masterchef);

        if (balance > 0) {
            _safeTransferFrom(lpToken, masterchef, recipient, balance);
        }

        // Deploy a kill dummy token that reports the expected balance to MasterChef
        // This satisfies the requirement: bal == newLpToken.balanceOf(address(this))
        MasterChefKillDummyToken dummy = new MasterChefKillDummyToken(balance, masterchef);

        emit Migration(address(lpToken), balance, recipient, address(dummy), block.number);

        return IERC20(address(dummy));
    }

    /// @dev Safe transferFrom that handles non-standard ERC20s (no return value)
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20TransferFrom.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }
}
