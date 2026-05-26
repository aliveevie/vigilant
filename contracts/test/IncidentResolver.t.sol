// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {RiskPolicy, PolicyState, ClaimState, Classification} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";

contract IncidentResolverTest is Base {
    function _setupActivePolicy() internal returns (uint256 policyId) {
        _deposit(underwriterA, 0, 50 ether);
        _deposit(underwriterB, 1, 50 ether);
        _deposit(underwriterC, 2, 50 ether);
        _scoreContract(coveredContract, 850, 1);

        RiskPolicy memory p = RiskPolicy({
            policyholder: policyholder,
            coveredContract: coveredContract,
            coverageAmount: 5 ether,
            riskTier: 1,
            premium: 0.5 ether,
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 100),
            nonce: 1
        });
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        policyId = policyManager.issue{value: p.premium}(p, sig);
    }

    function test_FileClaimAndPayoutOnExploitVerdict() public {
        uint256 policyId = _setupActivePolicy();
        uint256 balBefore = policyholder.balance;
        uint256 needed = resolver.quoteClaimDeposit();

        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: needed}(
            policyId, bytes32("evil-tx"), block.number
        );

        // Validators reach consensus on Exploit with 95% confidence.
        bytes memory result = abi.encode(uint8(Classification.Exploit), uint8(95), bytes32("verdict"));
        (,,, , , , , , , bool resolved) = _readPending(claimId);
        resolved; // unused

        // requestId == 1 (first platform call after risk-score requestId)
        // We track via resolver.claims(claimId).platformRequestId
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,, uint8 cls, uint8 conf) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Confirmed));
        assertEq(cls, uint8(Classification.Exploit));
        assertEq(conf, 95);

        assertEq(policyholder.balance, balBefore - needed + 5 ether);

        (, PolicyState ps, uint256 paidOut,,,,,,) = policyManager.policies(policyId);
        assertEq(uint8(ps), uint8(PolicyState.PaidOut));
        assertEq(paidOut, 5 ether);
    }

    function test_LowConfidenceRejects() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(uint8(Classification.Exploit), uint8(40), bytes32("low"));
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,,,) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Rejected));
    }

    function test_LegitimateRejects() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(uint8(Classification.Legitimate), uint8(99), bytes32("ok"));
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,,,) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Rejected));
    }

    function test_EscalateRequiresLargerSubcommittee() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(uint8(Classification.Inconclusive), uint8(60), bytes32("?"));
        platform.fulfil(requestId, result, ResponseStatus.Success);

        uint256 esc = resolver.quoteEscalationDeposit();
        assertGt(esc, needed);

        vm.prank(policyholder);
        resolver.escalate{value: esc}(claimId);
        (,,,, ClaimState st,,,) = resolver.claims(claimId);
        assertEq(uint8(st), uint8(ClaimState.Escalated));
    }

    function test_OnlyFilerCanEscalate() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(uint8(Classification.Legitimate), uint8(99), bytes32("ok"));
        platform.fulfil(requestId, result, ResponseStatus.Success);

        uint256 esc = resolver.quoteEscalationDeposit();
        vm.deal(address(0xBAD), esc);
        vm.prank(address(0xBAD));
        vm.expectRevert(Errors.NotPolicyManager.selector);
        resolver.escalate{value: esc}(claimId);
    }

    function _readPending(uint256) internal pure returns (uint256, uint256, bytes32, uint256, address, ClaimState, uint256, uint8, uint8, bool) {
        return (0, 0, bytes32(0), 0, address(0), ClaimState.None, 0, 0, 0, false);
    }
}
