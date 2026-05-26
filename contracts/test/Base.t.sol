// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockAgentPlatform} from "./mocks/MockAgentPlatform.sol";
import {CoverageVault} from "../src/vault/CoverageVault.sol";
import {PolicyManager} from "../src/PolicyManager.sol";
import {IncidentResolver} from "../src/IncidentResolver.sol";
import {SentinelRegistry} from "../src/SentinelRegistry.sol";
import {PremiumDistributor} from "../src/PremiumDistributor.sol";
import {Governor} from "../src/Governor.sol";
import {PolicyLib} from "../src/libraries/PolicyLib.sol";
import {RiskPolicy} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";

abstract contract Base is Test {
    MockAgentPlatform internal platform;
    CoverageVault internal vault;
    PolicyManager internal policyManager;
    IncidentResolver internal resolver;
    SentinelRegistry internal sentinels;
    PremiumDistributor internal distributor;
    Governor internal governor;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal underwriterA = address(0x1101);
    address internal underwriterB = address(0x1102);
    address internal underwriterC = address(0x1103);
    address internal policyholder;
    uint256 internal policyholderKey = 0xC0FFEE;
    address internal sentinel = address(0x9999);
    address internal coveredContract = address(0xC0DE);

    uint256 internal constant DEPOSIT_FLOOR = 0.01 ether;
    uint256 internal constant RISK_BUDGET = 0.005 ether;
    uint256 internal constant CLASSIFY_BUDGET = 0.005 ether;
    uint256 internal constant WARNING_BUDGET = 0.005 ether;
    uint64 internal constant TIER_TTL = 1000;
    uint8 internal constant CONFIDENCE_FLOOR = 70;
    uint8 internal constant WARNING_CONFIDENCE = 80;

    uint256 internal constant RISK_AGENT_ID = 1001;
    uint256 internal constant CLASSIFIER_AGENT_ID = 1002;
    uint256 internal constant WARNING_AGENT_ID = 1003;

    function setUp() public virtual {
        policyholder = vm.addr(policyholderKey);

        platform = new MockAgentPlatform(DEPOSIT_FLOOR);
        governor = new Governor(admin, 0);

        vault = new CoverageVault(address(governor));
        policyManager = new PolicyManager(
            address(platform),
            address(governor),
            address(vault),
            RISK_AGENT_ID,
            RISK_BUDGET,
            3,
            TIER_TTL
        );
        resolver = new IncidentResolver(
            address(platform),
            address(governor),
            address(policyManager),
            address(vault),
            CLASSIFIER_AGENT_ID,
            CLASSIFY_BUDGET,
            3,
            CONFIDENCE_FLOOR
        );
        sentinels = new SentinelRegistry(
            address(platform),
            address(governor),
            WARNING_AGENT_ID,
            WARNING_BUDGET,
            3,
            WARNING_CONFIDENCE,
            0.1 ether,
            0.05 ether
        );
        distributor = new PremiumDistributor(
            address(governor),
            address(vault),
            address(sentinels),
            treasury,
            7_000,
            2_000,
            1_000
        );

        // Wire vault.
        vm.prank(admin);
        governor.call(
            address(vault),
            0,
            abi.encodeWithSelector(
                CoverageVault.wire.selector,
                address(policyManager),
                address(resolver),
                address(distributor)
            )
        );
        vm.prank(admin);
        governor.call(
            address(policyManager),
            0,
            abi.encodeWithSelector(PolicyManager.setIncidentResolver.selector, address(resolver))
        );

        // Fund all parties.
        vm.deal(admin, 100 ether);
        vm.deal(policyholder, 100 ether);
        vm.deal(underwriterA, 100 ether);
        vm.deal(underwriterB, 100 ether);
        vm.deal(underwriterC, 100 ether);
        vm.deal(sentinel, 10 ether);
    }

    function _deposit(address u, uint8 tier, uint256 amount) internal returns (uint256 shares) {
        vm.prank(u);
        shares = vault.deposit{value: amount}(tier);
    }

    function _scoreContract(address target, uint16 score, uint8 tier) internal {
        uint256 needed = policyManager.quoteRiskScoreDeposit();
        vm.prank(policyholder);
        uint256 reqId = policyManager.requestRiskScore{value: needed}(target);
        bytes memory result = abi.encode(score, tier, bytes32("rationale"));
        platform.fulfil(reqId, result, ResponseStatus.Success);
    }

    bytes32 internal constant POLICY_TYPEHASH = keccak256(
        "RiskPolicy(address policyholder,address coveredContract,uint256 coverageAmount,uint8 riskTier,uint256 premium,uint64 startBlock,uint64 endBlock,uint256 nonce)"
    );

    function _signPolicy(RiskPolicy memory p) internal view returns (bytes memory sig) {
        bytes32 domain = policyManager.domainSeparator();
        bytes32 structHash = keccak256(
            abi.encode(
                POLICY_TYPEHASH,
                p.policyholder,
                p.coveredContract,
                p.coverageAmount,
                p.riskTier,
                p.premium,
                p.startBlock,
                p.endBlock,
                p.nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(policyholderKey, digest);
        sig = abi.encodePacked(r, s, v);
    }
}
