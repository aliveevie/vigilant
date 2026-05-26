// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {VaultShare} from "./VaultShare.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {RiskTier} from "../libraries/Types.sol";

/// @title CoverageVault
/// @notice Three-tranche underwriting vault. Holds the native settlement asset (SOMI / STT).
///         Each tranche issues a transferable ERC-20 share token (4626-like accounting on a native asset).
///         Tier C is first-loss; Tier A is paid out last. Capital backing active policies is locked.
contract CoverageVault {
    struct Tranche {
        VaultShare share;
        uint256 totalAssets;
        uint256 lockedAssets;
        uint16 premiumMultiplierBps;
    }

    Tranche[3] internal _tranches;

    address public immutable governor;
    address public policyManager;
    address public incidentResolver;
    address public premiumDistributor;
    bool internal _initialized;

    uint256 public reserve;

    modifier onlyGovernor() {
        if (msg.sender != governor) revert Errors.NotGovernor();
        _;
    }

    modifier onlyPolicyManager() {
        if (msg.sender != policyManager) revert Errors.NotPolicyManager();
        _;
    }

    modifier onlyIncidentResolver() {
        if (msg.sender != incidentResolver) revert Errors.NotIncidentResolver();
        _;
    }

    constructor(address governor_) {
        if (governor_ == address(0)) revert Errors.ZeroAddress();
        governor = governor_;

        _tranches[0].share = new VaultShare("Vigilant Tranche A", "vVIG-A", address(this));
        _tranches[1].share = new VaultShare("Vigilant Tranche B", "vVIG-B", address(this));
        _tranches[2].share = new VaultShare("Vigilant Tranche C", "vVIG-C", address(this));

        _tranches[0].premiumMultiplierBps = 6_000; // 0.6x — lowest yield, last loss
        _tranches[1].premiumMultiplierBps = 10_000; // 1.0x baseline
        _tranches[2].premiumMultiplierBps = 14_000; // 1.4x — highest yield, first loss
    }

    function wire(address policyManager_, address incidentResolver_, address premiumDistributor_)
        external
        onlyGovernor
    {
        if (_initialized) revert Errors.AlreadyInitialized();
        if (
            policyManager_ == address(0) || incidentResolver_ == address(0)
                || premiumDistributor_ == address(0)
        ) revert Errors.ZeroAddress();
        policyManager = policyManager_;
        incidentResolver = incidentResolver_;
        premiumDistributor = premiumDistributor_;
        _initialized = true;
    }

    // ---- Underwriter ops ----

    function deposit(uint8 tier) external payable returns (uint256 shares) {
        if (tier > 2) revert Errors.InvalidTier();
        if (msg.value == 0) revert Errors.ZeroAmount();

        Tranche storage t = _tranches[tier];
        uint256 supply = t.share.totalSupply();
        // 1:1 on bootstrap; share-pps thereafter.
        shares = (supply == 0 || t.totalAssets == 0) ? msg.value : (msg.value * supply) / t.totalAssets;

        t.totalAssets += msg.value;
        t.share.mint(msg.sender, shares);

        emit Events.CapitalDeposited(msg.sender, tier, msg.value, shares);
    }

    function withdraw(uint8 tier, uint256 shares) external returns (uint256 assets) {
        if (tier > 2) revert Errors.InvalidTier();
        if (shares == 0) revert Errors.ZeroAmount();

        Tranche storage t = _tranches[tier];
        uint256 supply = t.share.totalSupply();
        assets = (shares * t.totalAssets) / supply;

        uint256 available = t.totalAssets - t.lockedAssets;
        if (assets > available) revert Errors.TrancheLocked();

        t.totalAssets -= assets;
        t.share.burn(msg.sender, shares);

        (bool ok,) = msg.sender.call{value: assets}("");
        if (!ok) revert Errors.TransferFailed();

        emit Events.CapitalWithdrawn(msg.sender, tier, assets, shares);
    }

    // ---- Policy lifecycle ----

    /// @notice Lock `amount` of capital in the given tranche to back an active policy.
    function lock(uint8 tier, uint256 amount) external onlyPolicyManager {
        if (tier > 2) revert Errors.InvalidTier();
        Tranche storage t = _tranches[tier];
        uint256 available = t.totalAssets - t.lockedAssets;
        if (amount > available) revert Errors.InsufficientCapital();
        t.lockedAssets += amount;
        emit Events.CapitalLocked(tier, amount);
    }

    /// @notice Release locked capital — called when policies expire or are paid out.
    function unlock(uint8 tier, uint256 amount) external {
        if (msg.sender != policyManager && msg.sender != incidentResolver) {
            revert Errors.NotPolicyManager();
        }
        if (tier > 2) revert Errors.InvalidTier();
        Tranche storage t = _tranches[tier];
        if (amount > t.lockedAssets) amount = t.lockedAssets;
        t.lockedAssets -= amount;
        emit Events.CapitalUnlocked(tier, amount);
    }

    /// @notice Drain `amount` of native asset to `recipient` to settle a confirmed claim,
    ///         applying the loss waterfall (C → B → A).
    function absorb(uint256 amount, address recipient) external onlyIncidentResolver {
        if (recipient == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 remaining = amount;
        for (uint256 i = 3; i > 0; --i) {
            uint8 idx = uint8(i - 1);
            Tranche storage t = _tranches[idx];
            if (t.totalAssets == 0) continue;
            uint256 take = remaining > t.totalAssets ? t.totalAssets : remaining;
            t.totalAssets -= take;
            if (take > t.lockedAssets) {
                t.lockedAssets = 0;
            } else {
                t.lockedAssets -= take;
            }
            remaining -= take;
            emit Events.CapitalAbsorbed(idx, take);
            if (remaining == 0) break;
        }
        if (remaining > 0) revert Errors.InsufficientCapital();

        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert Errors.TransferFailed();
    }

    // ---- Premium intake ----

    /// @notice Accept a premium and redistribute by tranche multiplier (pull-payment).
    function receivePremium() external payable {
        if (msg.value == 0) revert Errors.ZeroAmount();
        emit Events.PremiumReceived(msg.value);

        // Multiplier-weighted by capital share.
        uint256 weighted0 =
            _tranches[0].totalAssets * uint256(_tranches[0].premiumMultiplierBps);
        uint256 weighted1 =
            _tranches[1].totalAssets * uint256(_tranches[1].premiumMultiplierBps);
        uint256 weighted2 =
            _tranches[2].totalAssets * uint256(_tranches[2].premiumMultiplierBps);
        uint256 totalWeight = weighted0 + weighted1 + weighted2;

        if (totalWeight == 0) {
            reserve += msg.value;
            emit Events.PremiumDistributed(0, 0, 0, msg.value);
            return;
        }

        uint256 net = msg.value;
        uint256 reserveCut = net / 10; // 10% to reserve
        net -= reserveCut;
        reserve += reserveCut;

        uint256 toA = (net * weighted0) / totalWeight;
        uint256 toB = (net * weighted1) / totalWeight;
        uint256 toC = net - toA - toB;

        _tranches[0].totalAssets += toA;
        _tranches[1].totalAssets += toB;
        _tranches[2].totalAssets += toC;

        emit Events.PremiumDistributed(toA, toB, toC, reserveCut);
    }

    /// @notice Sweep reserve to the configured premium distributor.
    function sweepReserve(uint256 amount) external onlyGovernor {
        if (amount > reserve) amount = reserve;
        reserve -= amount;
        (bool ok,) = premiumDistributor.call{value: amount}("");
        if (!ok) revert Errors.TransferFailed();
    }

    // ---- Governor ops ----

    function setPremiumMultiplier(uint8 tier, uint16 bps) external onlyGovernor {
        if (tier > 2) revert Errors.InvalidTier();
        _tranches[tier].premiumMultiplierBps = bps;
    }

    function setPremiumDistributor(address d) external onlyGovernor {
        if (d == address(0)) revert Errors.ZeroAddress();
        premiumDistributor = d;
    }

    // ---- Views ----

    function trancheTotals(uint8 tier)
        external
        view
        returns (uint256 totalAssets, uint256 lockedAssets, uint256 totalShares, uint16 multiplierBps)
    {
        if (tier > 2) revert Errors.InvalidTier();
        Tranche storage t = _tranches[tier];
        return (t.totalAssets, t.lockedAssets, t.share.totalSupply(), t.premiumMultiplierBps);
    }

    function shareToken(uint8 tier) external view returns (address) {
        if (tier > 2) revert Errors.InvalidTier();
        return address(_tranches[tier].share);
    }

    function previewDeposit(uint8 tier, uint256 assets) external view returns (uint256) {
        if (tier > 2) revert Errors.InvalidTier();
        Tranche storage t = _tranches[tier];
        uint256 supply = t.share.totalSupply();
        return (supply == 0 || t.totalAssets == 0) ? assets : (assets * supply) / t.totalAssets;
    }

    function previewRedeem(uint8 tier, uint256 shares) external view returns (uint256) {
        if (tier > 2) revert Errors.InvalidTier();
        Tranche storage t = _tranches[tier];
        uint256 supply = t.share.totalSupply();
        return supply == 0 ? 0 : (shares * t.totalAssets) / supply;
    }

    function totalCapital() external view returns (uint256) {
        return _tranches[0].totalAssets + _tranches[1].totalAssets + _tranches[2].totalAssets;
    }

    function totalLocked() external view returns (uint256) {
        return _tranches[0].lockedAssets + _tranches[1].lockedAssets + _tranches[2].lockedAssets;
    }

    receive() external payable {
        // Bare deposits go to reserve.
        reserve += msg.value;
    }
}
