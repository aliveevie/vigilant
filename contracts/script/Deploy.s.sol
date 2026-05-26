// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Governor} from "../src/Governor.sol";
import {CoverageVault} from "../src/vault/CoverageVault.sol";
import {PolicyManager} from "../src/PolicyManager.sol";
import {IncidentResolver} from "../src/IncidentResolver.sol";
import {SentinelRegistry} from "../src/SentinelRegistry.sol";
import {PremiumDistributor} from "../src/PremiumDistributor.sol";

/// @notice Production deploy script.
/// @dev Environment variables (set via .env or shell):
///        VIG_PLATFORM           — address of the SomniaAgents platform on the target chain
///        VIG_GOVERNOR_ADMIN     — EOA that will hold the governor admin key
///        VIG_TREASURY           — treasury recipient of the premium split
///        VIG_RISK_AGENT_ID      — uint256 agent id of the RiskScoringAgent
///        VIG_CLASSIFIER_AGENT_ID — uint256 agent id of the ExploitClassifierAgent
///        VIG_WARNING_AGENT_ID   — uint256 agent id of the WarningVerifierAgent
///        VIG_TIMELOCK_DELAY     — uint256 seconds for the governor timelock
contract Deploy is Script {
    struct Ctx {
        address platformAddr;
        address admin;
        address treasury;
        uint256 riskAgentId;
        uint256 classifierAgentId;
        uint256 warningAgentId;
        uint64 timelockDelay;
    }

    function _loadCtx() internal view returns (Ctx memory c) {
        c.platformAddr = vm.envAddress("VIG_PLATFORM");
        c.admin = vm.envAddress("VIG_GOVERNOR_ADMIN");
        c.treasury = vm.envAddress("VIG_TREASURY");
        c.riskAgentId = vm.envUint("VIG_RISK_AGENT_ID");
        c.classifierAgentId = vm.envUint("VIG_CLASSIFIER_AGENT_ID");
        c.warningAgentId = vm.envUint("VIG_WARNING_AGENT_ID");
        c.timelockDelay = uint64(vm.envUint("VIG_TIMELOCK_DELAY"));
    }

    function run() external {
        Ctx memory c = _loadCtx();

        vm.startBroadcast();

        Governor governor = new Governor(c.admin, c.timelockDelay);
        CoverageVault vault = new CoverageVault(address(governor));

        PolicyManager pm = _deployPolicyManager(c, address(governor), address(vault));
        IncidentResolver ir = _deployResolver(c, address(governor), address(pm), address(vault));
        SentinelRegistry sr = _deploySentinels(c, address(governor));
        PremiumDistributor pd =
            _deployDistributor(address(governor), address(vault), address(sr), c.treasury);

        governor.call(
            address(vault),
            0,
            abi.encodeWithSelector(
                CoverageVault.wire.selector, address(pm), address(ir), address(pd)
            )
        );
        governor.call(
            address(pm),
            0,
            abi.encodeWithSelector(PolicyManager.setIncidentResolver.selector, address(ir))
        );

        vm.stopBroadcast();

        console2.log("Governor          ", address(governor));
        console2.log("CoverageVault     ", address(vault));
        console2.log("PolicyManager     ", address(pm));
        console2.log("IncidentResolver  ", address(ir));
        console2.log("SentinelRegistry  ", address(sr));
        console2.log("PremiumDistributor", address(pd));
    }

    function _deployPolicyManager(Ctx memory c, address gov, address vault)
        internal
        returns (PolicyManager)
    {
        return new PolicyManager(c.platformAddr, gov, vault, c.riskAgentId, 0.005 ether, 3, 1_000);
    }

    function _deployResolver(Ctx memory c, address gov, address pm, address vault)
        internal
        returns (IncidentResolver)
    {
        return
            new IncidentResolver(c.platformAddr, gov, pm, vault, c.classifierAgentId, 0.005 ether, 3, 75);
    }

    function _deploySentinels(Ctx memory c, address gov) internal returns (SentinelRegistry) {
        return new SentinelRegistry(
            c.platformAddr, gov, c.warningAgentId, 0.005 ether, 3, 80, 0.05 ether, 0.025 ether
        );
    }

    function _deployDistributor(address gov, address vault, address sentinels, address treasury)
        internal
        returns (PremiumDistributor)
    {
        return new PremiumDistributor(gov, vault, sentinels, treasury, 7_000, 2_000, 1_000);
    }
}
