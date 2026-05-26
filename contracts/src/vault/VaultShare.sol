// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Errors} from "../libraries/Errors.sol";

/// @notice Transferable ERC-20 share token for a single CoverageVault tranche.
/// @dev Mint/burn is gated to the vault contract that deployed this token.
contract VaultShare is ERC20 {
    address public immutable vault;

    constructor(string memory name_, string memory symbol_, address vault_) ERC20(name_, symbol_) {
        if (vault_ == address(0)) revert Errors.ZeroAddress();
        vault = vault_;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert Errors.NotPolicyManager();
        _;
    }

    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }
}
