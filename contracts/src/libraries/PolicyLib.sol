// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RiskPolicy} from "./Types.sol";

/// @notice EIP-712 hashing helpers for the `RiskPolicy` struct.
library PolicyLib {
    bytes32 internal constant RISK_POLICY_TYPEHASH = keccak256(
        "RiskPolicy(address policyholder,address coveredContract,uint256 coverageAmount,uint8 riskTier,uint256 premium,uint64 startBlock,uint64 endBlock,uint256 nonce)"
    );

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    function structHash(RiskPolicy calldata p) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RISK_POLICY_TYPEHASH,
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
    }

    function domainSeparator(string memory name, string memory version, address verifyingContract)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
    }

    function digest(bytes32 domain, bytes32 hashed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domain, hashed));
    }
}
