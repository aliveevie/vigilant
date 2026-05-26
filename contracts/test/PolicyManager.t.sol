// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {RiskPolicy, PolicyState} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";

contract PolicyManagerTest is Base {
    function _stockVault() internal {
        _deposit(underwriterA, 0, 50 ether);
        _deposit(underwriterB, 1, 50 ether);
        _deposit(underwriterC, 2, 50 ether);
    }

    function _basicPolicy(uint8 tier) internal view returns (RiskPolicy memory p) {
        p = RiskPolicy({
            policyholder: policyholder,
            coveredContract: coveredContract,
            coverageAmount: 5 ether,
            riskTier: tier,
            premium: 0.5 ether,
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 100),
            nonce: 1
        });
    }

    function test_RequestRiskScoreCachesTier() public {
        _scoreContract(coveredContract, 850, 1);
        (uint8 tier, uint16 score,, uint64 expires, ) = policyManager.coveredContractTier(coveredContract);
        assertEq(tier, 1);
        assertEq(score, 850);
        assertGt(expires, block.number);
    }

    function test_IssuePolicyHappyPath() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);

        RiskPolicy memory p = _basicPolicy(1);
        bytes memory sig = _signPolicy(p);

        vm.prank(policyholder);
        uint256 id = policyManager.issue{value: p.premium}(p, sig);
        assertEq(id, 1);

        (, PolicyState state, , address holder,, uint256 coverage, uint8 tier,,) =
            policyManager.policies(id);
        assertEq(uint8(state), uint8(PolicyState.Active));
        assertEq(holder, policyholder);
        assertEq(coverage, 5 ether);
        assertEq(tier, 1);

        (, uint256 locked,,) = vault.trancheTotals(1);
        assertEq(locked, 5 ether);
    }

    function test_IssueRevertsTierMismatch() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);

        RiskPolicy memory p = _basicPolicy(0); // expects A but cache is B
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        vm.expectRevert(Errors.TierMismatch.selector);
        policyManager.issue{value: p.premium}(p, sig);
    }

    function test_IssueRevertsTierNotCached() public {
        _stockVault();
        RiskPolicy memory p = _basicPolicy(1);
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        vm.expectRevert(Errors.TierNotCached.selector);
        policyManager.issue{value: p.premium}(p, sig);
    }

    function test_IssueRevertsTierExpired() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);
        vm.roll(block.number + TIER_TTL + 1);

        RiskPolicy memory p = _basicPolicy(1);
        p.startBlock = uint64(block.number);
        p.endBlock = uint64(block.number + 100);
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        vm.expectRevert(Errors.TierExpired.selector);
        policyManager.issue{value: p.premium}(p, sig);
    }

    function test_IssueRevertsInvalidSignature() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);

        RiskPolicy memory p = _basicPolicy(1);
        bytes memory badSig = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));
        vm.prank(policyholder);
        vm.expectRevert();
        policyManager.issue{value: p.premium}(p, badSig);
    }

    function test_NonceReplayProtection() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);

        RiskPolicy memory p = _basicPolicy(1);
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        policyManager.issue{value: p.premium}(p, sig);

        vm.prank(policyholder);
        vm.expectRevert(Errors.InvalidSignature.selector);
        policyManager.issue{value: p.premium}(p, sig);
    }

    function test_ExpireUnlocksCapital() public {
        _stockVault();
        _scoreContract(coveredContract, 850, 1);
        RiskPolicy memory p = _basicPolicy(1);
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        uint256 id = policyManager.issue{value: p.premium}(p, sig);

        vm.roll(uint256(p.endBlock) + 1);
        policyManager.expire(id);

        (, uint256 locked,,) = vault.trancheTotals(1);
        assertEq(locked, 0);
    }

    function test_RiskScoreFailureBumpsCircuit() public {
        uint256 reqId;
        for (uint256 i = 0; i < 5; ++i) {
            uint256 needed = policyManager.quoteRiskScoreDeposit();
            vm.prank(policyholder);
            reqId = policyManager.requestRiskScore{value: needed}(address(uint160(0xDEAD + i)));
            platform.fulfil(reqId, "", ResponseStatus.Failed);
        }
        assertTrue(policyManager.circuitOpen());
    }
}
