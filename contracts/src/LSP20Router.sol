// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";

/**
 * @title LSP20Router
 * @notice Router that delegates LSP20 pre/post call verification to child verifier contracts.
 * @dev
 * - Maintains a `defaultVerifier` and per-selector `verifierForSelector` mappings for each target.
 * - Emits `PreRouted` and `PostRouted` events to aid off-chain tracing and debugging.
 * - When a child verifier requests post-call verification (last byte == 0x01), the router
 *   records the child and forwards the post-call result to the child for final checks.
 */
contract LSP20Router is ILSP20 {
    event DefaultVerifierSet(address indexed target, address indexed verifier);
    event VerifierSet(address indexed target, bytes4 indexed selector, address indexed verifier);
    event TargetPaused(address indexed target, bool paused);
    event PreRouted(
        bytes32 indexed callHash,
        address indexed target,
        bytes4 indexed selector,
        address child,
        address requestor,
        address caller,
        uint256 value,
        bytes32 callDataHash
    );
    event PostRouted(
        bytes32 indexed callHash,
        address indexed target,
        address child,
        bytes4 childStatus,
        bytes32 callResultHash
    );

    address public owner;

    mapping(address => address) public defaultVerifier; // target => verifier
    mapping(address => mapping(bytes4 => address)) public verifierForSelector; // target => selector
        // => verifier
    mapping(bytes32 => address) private _verifierUsed; // callHash => child verifier address
    mapping(address => bool) public paused; // target => paused

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNABLE: not owner");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OWNABLE: zero");
        owner = newOwner;
    }

    function setDefaultVerifier(address target, address verifier) external onlyOwner {
        defaultVerifier[target] = verifier;
        emit DefaultVerifierSet(target, verifier);
    }

    function setVerifierForSelector(address target, bytes4 selector, address verifier)
        external
        onlyOwner
    {
        verifierForSelector[target][selector] = verifier;
        emit VerifierSet(target, selector, verifier);
    }

    function setVerifierForSelectors(address target, bytes4[] calldata selectors, address verifier)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < selectors.length; i++) {
            verifierForSelector[target][selectors[i]] = verifier;
            emit VerifierSet(target, selectors[i], verifier);
        }
    }

    function pauseTarget(address target, bool _paused) external onlyOwner {
        paused[target] = _paused;
        emit TargetPaused(target, _paused);
    }

    function _child(address target, bytes4 selector) internal view returns (address) {
        address v = verifierForSelector[target][selector];
        if (v != address(0)) return v;
        return defaultVerifier[target];
    }

    function lsp20VerifyCall(
        address requestor,
        address target,
        address caller,
        uint256 value,
        bytes memory callData
    ) external override returns (bytes4 returnedStatus) {
        require(!paused[target], "ROUTER: paused");
        require(callData.length >= 4, "ROUTER: bad calldata");

        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }
        address child = _child(target, selector);
        require(child != address(0), "ROUTER: no verifier");

        bytes32 callHash = keccak256(abi.encode(requestor, target, caller, value, callData));
        emit PreRouted(
            callHash, target, selector, child, requestor, caller, value, keccak256(callData)
        );

        // delegate pre-call to child
        (bool ok, bytes memory ret) = child.call(
            abi.encodeWithSelector(
                ILSP20.lsp20VerifyCall.selector, requestor, target, caller, value, callData
            )
        );
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        require(ret.length >= 32, "ROUTER: child bad ret");
        returnedStatus = abi.decode(ret, (bytes4));

        // if child asked for post-call (last byte == 0x01), remember by callHash
        if ((uint32(returnedStatus) & 0xff) == 0x01) _verifierUsed[callHash] = child;
    }

    function lsp20VerifyCallResult(bytes32 callHash, bytes memory callResult)
        external
        override
        returns (bytes4)
    {
        address child = _verifierUsed[callHash];
        if (child == address(0)) {
            // no post-call requested
            return ILSP20.lsp20VerifyCallResult.selector;
        }
        delete _verifierUsed[callHash];
        (bool ok, bytes memory ret) = child.call(
            abi.encodeWithSelector(ILSP20.lsp20VerifyCallResult.selector, callHash, callResult)
        );
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        require(ret.length >= 32, "ROUTER: child post bad ret");
        bytes4 status = abi.decode(ret, (bytes4));
        emit PostRouted(callHash, msg.sender, child, status, keccak256(callResult));
        return status;
    }
}
