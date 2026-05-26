// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Base.t.sol";
import {Errors} from "../src/libraries/Errors.sol";
import {Classification} from "../src/libraries/Types.sol";
import {ResponseStatus} from "../src/interfaces/IAgentRequester.sol";

contract SentinelRegistryTest is Base {
    function test_CorrectWarningPaysBounty() public {
        // Fund reserve from admin so bounty can be paid.
        vm.prank(admin);
        sentinels.fundReserve{value: 1 ether}();

        uint256 needed = sentinels.quoteWarningDeposit();
        uint256 balBefore = sentinel.balance;

        vm.prank(sentinel);
        uint256 wid = sentinels.submitWarning{value: needed}(
            coveredContract, bytes32("hack-tx"), block.number
        );
        (,,,,, uint256 reqId,,) = sentinels.warnings(wid);

        bytes memory result = abi.encode(uint8(Classification.Exploit), uint8(95), bytes32("v"));
        platform.fulfil(reqId, result, ResponseStatus.Success);

        // Deposit returned + bounty paid.
        assertGt(sentinel.balance, balBefore - needed + 0.05 ether);
        assertGt(sentinels.getScore(sentinel), 0);
        assertTrue(sentinels.coveragePaused(coveredContract));
    }

    function test_IncorrectWarningForfeitsDeposit() public {
        uint256 needed = sentinels.quoteWarningDeposit();
        uint256 balBefore = sentinel.balance;

        vm.prank(sentinel);
        uint256 wid = sentinels.submitWarning{value: needed}(
            coveredContract, bytes32("noop-tx"), block.number
        );
        (,,,,, uint256 reqId,,) = sentinels.warnings(wid);

        bytes memory result = abi.encode(uint8(Classification.Legitimate), uint8(99), bytes32("ok"));
        platform.fulfil(reqId, result, ResponseStatus.Success);

        assertEq(sentinels.getScore(sentinel), 0);
        assertEq(sentinel.balance, balBefore - needed);
        assertEq(sentinels.protocolReserve(), 0.05 ether);
    }
}
