// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {CoverageVault} from "./vault/CoverageVault.sol";
import {SentinelRegistry} from "./SentinelRegistry.sol";

/// @title PremiumDistributor
/// @notice Pull-payment router for protocol revenue. Splits inflows between the CoverageVault reserve,
///         the sentinel bounty pool, and a governor-controlled treasury.
contract PremiumDistributor {
    address public immutable governor;
    CoverageVault public immutable vault;
    SentinelRegistry public immutable sentinels;
    address public treasury;

    uint16 public vaultBps;
    uint16 public sentinelBps;
    uint16 public treasuryBps;

    uint256 public accruedVault;
    uint256 public accruedSentinel;
    uint256 public accruedTreasury;

    modifier onlyGovernor() {
        if (msg.sender != governor) revert Errors.NotGovernor();
        _;
    }

    constructor(
        address governor_,
        address vault_,
        address sentinels_,
        address treasury_,
        uint16 vaultBps_,
        uint16 sentinelBps_,
        uint16 treasuryBps_
    ) {
        if (
            governor_ == address(0) || vault_ == address(0) || sentinels_ == address(0)
                || treasury_ == address(0)
        ) revert Errors.ZeroAddress();
        if (uint256(vaultBps_) + sentinelBps_ + treasuryBps_ != 10_000) {
            revert Errors.InvalidConfidence();
        }
        governor = governor_;
        vault = CoverageVault(payable(vault_));
        sentinels = SentinelRegistry(payable(sentinels_));
        treasury = treasury_;
        vaultBps = vaultBps_;
        sentinelBps = sentinelBps_;
        treasuryBps = treasuryBps_;
    }

    function setSplits(uint16 vaultBps_, uint16 sentinelBps_, uint16 treasuryBps_)
        external
        onlyGovernor
    {
        if (uint256(vaultBps_) + sentinelBps_ + treasuryBps_ != 10_000) {
            revert Errors.InvalidConfidence();
        }
        vaultBps = vaultBps_;
        sentinelBps = sentinelBps_;
        treasuryBps = treasuryBps_;
    }

    function setTreasury(address t) external onlyGovernor {
        if (t == address(0)) revert Errors.ZeroAddress();
        treasury = t;
    }

    /// @notice Accept inbound funds and split into pull buckets.
    receive() external payable {
        uint256 toVault = (msg.value * vaultBps) / 10_000;
        uint256 toSentinel = (msg.value * sentinelBps) / 10_000;
        uint256 toTreasury = msg.value - toVault - toSentinel;
        accruedVault += toVault;
        accruedSentinel += toSentinel;
        accruedTreasury += toTreasury;
    }

    function pushToVault() external {
        uint256 amt = accruedVault;
        accruedVault = 0;
        vault.receivePremium{value: amt}();
    }

    function pushToSentinel() external {
        uint256 amt = accruedSentinel;
        accruedSentinel = 0;
        sentinels.fundReserve{value: amt}();
    }

    function pushToTreasury() external {
        uint256 amt = accruedTreasury;
        accruedTreasury = 0;
        (bool ok,) = treasury.call{value: amt}("");
        if (!ok) revert Errors.TransferFailed();
    }
}
