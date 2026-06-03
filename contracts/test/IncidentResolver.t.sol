// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {RiskPolicy, PolicyState, ClaimState} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";
import {IncidentResolver} from "../src/IncidentResolver.sol";

contract IncidentResolverTest is Base {
    string internal constant VERDICT_EXPLOIT = "Exploit";
    string internal constant VERDICT_NOT_EXPLOIT = "NotExploit";
    string internal constant VERDICT_INCONCLUSIVE = "Inconclusive";

    function _setupActivePolicy() internal returns (uint256 policyId) {
        _deposit(underwriterA, 0, 50 ether);
        _deposit(underwriterB, 1, 50 ether);
        _deposit(underwriterC, 2, 50 ether);
        // score 50 → tier B (1).
        _scoreContract(coveredContract, 50, 0);

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

        (,,,,, uint256 requestId,,) = resolver.claims(claimId);
        bytes memory result = abi.encode(VERDICT_EXPLOIT);
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,, uint8 cls,) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Confirmed));
        assertEq(cls, 1); // 1 == exploit

        assertEq(policyholder.balance, balBefore - needed + 5 ether);

        (, PolicyState ps, uint256 paidOut,,,,,,) = policyManager.policies(policyId);
        assertEq(uint8(ps), uint8(PolicyState.PaidOut));
        assertEq(paidOut, 5 ether);
    }

    function test_NotExploitRejects() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId =
            resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(VERDICT_NOT_EXPLOIT);
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,,,) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Rejected));
    }

    function test_InconclusiveRejects() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId =
            resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(VERDICT_INCONCLUSIVE);
        platform.fulfil(requestId, result, ResponseStatus.Success);

        (,,,, ClaimState state,,,) = resolver.claims(claimId);
        assertEq(uint8(state), uint8(ClaimState.Rejected));
    }

    function test_EscalateRequiresLargerSubcommittee() public {
        uint256 policyId = _setupActivePolicy();
        uint256 needed = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId =
            resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(VERDICT_INCONCLUSIVE);
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
        uint256 claimId =
            resolver.fileClaim{value: needed}(policyId, bytes32("tx"), block.number);
        (,,,,, uint256 requestId,,) = resolver.claims(claimId);

        bytes memory result = abi.encode(VERDICT_NOT_EXPLOIT);
        platform.fulfil(requestId, result, ResponseStatus.Success);

        uint256 esc = resolver.quoteEscalationDeposit();
        vm.deal(address(0xBAD), esc);
        vm.prank(address(0xBAD));
        vm.expectRevert(Errors.NotPolicyManager.selector);
        resolver.escalate{value: esc}(claimId);
    }
}
