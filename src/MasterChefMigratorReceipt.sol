// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >= 0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20 as OZ_IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MasterChefReceiptToken
/// @notice Minimal mintable ERC20 receipt token issued during MasterChef migration
/// @dev Fully ERC20-compliant so MasterChef.withdraw() and emergencyWithdraw() can
/// safeTransfer these tokens to users as IOUs for their LP positions.
contract MasterChefReceiptToken is ERC20, ERC20Burnable {
    /// @notice The address allowed to mint tokens (the migrator contract)
    address public immutable minter;

    /// @notice Creates a receipt token with a designated minter
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _minter The address allowed to mint (should be the migrator)
    constructor(string memory _name, string memory _symbol, address _minter) ERC20(_name, _symbol) {
        minter = _minter;
    }

    /// @notice Mints tokens to a recipient, restricted to the minter
    /// @param to The address to mint to
    /// @param amount The amount to mint
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "only minter");
        _mint(to, amount);
    }
}

/// @title MasterChefMigratorReceipt
/// @author Sushi
/// @notice Migrator contract that transfers LP tokens to a recipient and issues ERC20 receipt tokens
/// @dev This contract is designed to be set as the migrator on the MasterChef (V1) contract on Ethereum
/// mainnet. Unlike MasterChefMigratorTransfer which uses a DummyToken, this migrator deploys a fully
/// ERC20-compliant receipt token so that users can still withdraw() and emergencyWithdraw() after
/// migration, receiving transferable receipt tokens as IOUs for their LP positions.
///
/// Flow:
/// 1. Owner calls MasterChef.setMigrator(address(this))
/// 2. Operator calls MasterChef.migrate(pid) for each pool
/// 3. MasterChef calls safeApprove for LP tokens and calls migrate()
/// 4. This contract verifies tx.origin == operator
/// 5. Transfers LP tokens to recipient via SafeERC20
/// 6. Deploys a MasterChefReceiptToken with matching balance for MasterChef
/// 7. MasterChef stores the receipt token as the new LP token
/// 8. Users can withdraw() to receive transferable receipt tokens
contract MasterChefMigratorReceipt {
    using SafeERC20 for OZ_IERC20;

    /// @notice The MasterChef contract that is allowed to call migrate
    address public immutable masterchef;

    /// @notice The address allowed to initiate migrations (checked via tx.origin)
    address public immutable operator;

    /// @notice The recipient address that will receive all migrated LP tokens
    address public immutable recipient;

    /// @notice Mapping from original LP token to deployed receipt token (doubles as double-migrate guard)
    mapping(address => address) public migrated;

    /// @notice Emitted when LP tokens are migrated to the recipient
    event Migrated(address indexed lpToken, address indexed receiptToken, address indexed recipient, uint256 amount);

    /// @notice Emitted when a new receipt token is deployed
    event ReceiptDeployed(address indexed lpToken, address indexed receiptToken, string name, string symbol);

    /// @notice Initializes the migrator with the MasterChef, operator, and recipient addresses
    /// @param _masterchef The MasterChef contract address that will call migrate
    /// @param _operator The EOA allowed to initiate migrations via MasterChef.migrate()
    /// @param _recipient The address that will receive all LP tokens (e.g., multisig)
    constructor(address _masterchef, address _operator, address _recipient) {
        require(_operator != address(0), "zero operator");
        require(_recipient != address(0), "zero recipient");
        masterchef = _masterchef;
        operator = _operator;
        recipient = _recipient;
    }

    /// @notice Migrates LP tokens by transferring them to the recipient and returning a receipt token
    /// @dev Called by MasterChef during the migration process. MasterChef will have already
    /// called safeApprove for this contract to spend its LP tokens before calling this function.
    /// @param token The LP token to migrate
    /// @return The receipt token that replaces the LP token in MasterChef
    function migrate(IERC20 token) external returns (IERC20) {
        require(msg.sender == masterchef, "only masterchef");
        require(tx.origin == operator, "only operator");
        require(migrated[address(token)] == address(0), "already migrated");

        uint256 balance = token.balanceOf(masterchef);
        require(balance > 0, "zero balance");

        // Transfer LP tokens to recipient using SafeERC20
        OZ_IERC20(address(token)).safeTransferFrom(masterchef, recipient, balance);

        // Build name/symbol from original token metadata
        string memory receiptName;
        string memory receiptSymbol;
        try IERC20Metadata(address(token)).symbol() returns (string memory sym) {
            receiptName = string.concat("Sushi MasterChef Receipt: ", sym);
            receiptSymbol = string.concat("mcR-", sym);
        } catch {
            receiptName = "Sushi MasterChef Receipt";
            receiptSymbol = "mcRECEIPT";
        }

        // Deploy receipt token and mint balance to MasterChef
        MasterChefReceiptToken receipt = new MasterChefReceiptToken(receiptName, receiptSymbol, address(this));
        receipt.mint(masterchef, balance);

        // Record migration
        migrated[address(token)] = address(receipt);

        emit ReceiptDeployed(address(token), address(receipt), receiptName, receiptSymbol);
        emit Migrated(address(token), address(receipt), recipient, balance);

        return IERC20(address(receipt));
    }
}
