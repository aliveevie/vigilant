// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {RiskPolicy, PolicyState, ClaimState} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";

contract EndToEndTest is Base {
    function test_FullLifecycle_RiskScore_Issue_Claim_Payout() public {
        // 1) Underwriters fund all three tranches.
        _deposit(underwriterA, 0, 30 ether);
        _deposit(underwriterB, 1, 30 ether);
        _deposit(underwriterC, 2, 30 ether);
        assertEq(vault.totalCapital(), 90 ether);

        // 2) Risk scoring of a covered contract — score 85 → tier C (2).
        uint256 riskReqDeposit = policyManager.quoteRiskScoreDeposit();
        vm.prank(policyholder);
        uint256 riskReq =
            policyManager.requestRiskScore{value: riskReqDeposit}(coveredContract);
        platform.fulfil(riskReq, abi.encode(int256(85)), ResponseStatus.Success);

        // 3) Policyholder signs an EIP-712 envelope matching the cached tier (C) and issues.
        RiskPolicy memory p = RiskPolicy({
            policyholder: policyholder,
            coveredContract: coveredContract,
            coverageAmount: 10 ether,
            riskTier: 2,
            premium: 1 ether,
            startBlock: uint64(block.number),
            endBlock: uint64(block.number + 200),
            nonce: 1
        });
        bytes memory sig = _signPolicy(p);
        vm.prank(policyholder);
        uint256 policyId = policyManager.issue{value: 1 ether}(p, sig);

        (, uint256 lockedC,,) = vault.trancheTotals(2);
        assertEq(lockedC, 10 ether);

        // 4) Filer reports an exploit transaction.
        vm.roll(block.number + 5);
        uint256 claimDeposit = resolver.quoteClaimDeposit();
        vm.prank(policyholder);
        uint256 claimId = resolver.fileClaim{value: claimDeposit}(
            policyId, bytes32("exploit-tx"), block.number
        );

        // 5) Validator consensus on Exploit verdict.
        (,,,,, uint256 reqId,,) = resolver.claims(claimId);
        platform.fulfil(reqId, abi.encode(string("Exploit")), ResponseStatus.Success);

        // 6) Atomic payout from tranche C; policy marked PaidOut.
        (,,,, ClaimState cs,,,) = resolver.claims(claimId);
        assertEq(uint8(cs), uint8(ClaimState.Confirmed));

        (, PolicyState ps,,,,,,,) = policyManager.policies(policyId);
        assertEq(uint8(ps), uint8(PolicyState.PaidOut));

        (uint256 tcAfter,,,) = vault.trancheTotals(2);
        // C tranche: 30e initial + premium share - 10e absorbed.
        // Premium 1e, reserve 10%=0.1e. Net 0.9e split by weighted capital
        // (6000*30, 10000*30, 14000*30) -> 0.9 * 14/30 = 0.42e to C.
        assertEq(tcAfter, 30 ether + 0.42 ether - 10 ether);
    }
}
