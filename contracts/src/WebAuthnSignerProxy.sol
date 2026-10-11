// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {WebAuthn} from "./WebAuthn.sol";

interface IWebAuthnAuthoriser {
    function authoriseExecUP(
        address profile,
        bytes32 credentialId,
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload);

    function authoriseSetDataBatchUP(
        address profile,
        bytes32 credentialId,
        bytes32[] calldata dataKeys,
        bytes[] calldata dataValues,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload);

    function authoriseExecuteBatchUP(
        address profile,
        bytes32 credentialId,
        uint256[] calldata operationTypes,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload);
}

interface ILSP6KeyManagerLike {
    function execute(bytes calldata payload) external payable returns (bytes memory);
    /// @dev The LSP6 standard getter (`LSP6KeyManagerCore.target`, LUKSO lsp6-contracts 0.15).
    function target() external view returns (address);
    /// @dev The name early Key Managers and this repo's test mocks use.
    function account() external view returns (address);
}

interface IOwnable {
    function owner() external view returns (address);
}

/// @title WebAuthnSignerProxy
/// @notice One contract per (profile, credential). **This** is the LSP6 controller the user's
///         passkey drives — not the shared `WebAuthnController`.
///
/// @dev WHY THE CALL ORDER IS INVERTED, AND WHY THAT IS THE WHOLE CONTRACT.
///      An earlier design had `WebAuthnController.executeUPViaKeyManager(...)` call
///      `ILSP6KeyManager(keyManager).execute(payload)` itself. `LSP6KeyManagerCore._execute`
///      verifies permissions against `msg.sender`, so the permission subject was the
///      **controller — a shared singleton every user routes through** — and the per-proxy
///      `AddressPermissions` this design exists to leverage were never read.
///
///      Inverting one hop fixes it. The controller now only VERIFIES the assertion and consumes
///      the nonce, returning the payload; **this contract makes the KeyManager call**, so
///      `msg.sender` at the KeyManager is a per-user address that can hold its own permission
///      bitmap. Same digests, same assertions, same client — a different caller.
///
/// @dev AND GAS SPONSORSHIP SURVIVES WITHOUT `executeRelayCall`. There is deliberately no
///      `msg.sender` check on `executeUP`: the assertion IS the authorisation, so anyone may submit
///      and the user pays nothing. `LSP6`'s relay-call path cannot serve here in any case —
///      it recovers the signer with `ECDSA.recover`, secp256k1, in LSP25MultiChannelNonce.sol at
///      line 94, and a P-256 passkey can never be that signer.
///
/// @dev NOTHING IN THIS CONTRACT'S STATE IS A FREE PARAMETER, AND THAT IS A SECURITY PROPERTY.
///      The address is `CREATE2(controller, keccak256(abi.encode(profile, credentialId)), <clone of
///      a fixed implementation>)`. Both `initialize` arguments beyond the controller are exactly the
///      values hashed into the salt, so **a front-runner who deploys at the predicted address can
///      only produce an identical contract.** In particular the Key Manager is NOT stored: it is
///      resolved from the profile at call time, with reverse binding. Storing it would have been the
///      one value an attacker could choose.
contract WebAuthnSignerProxy {
    IWebAuthnAuthoriser public controller;
    address public profile;
    bytes32 public credentialId;
    bool public initialized;

    error AlreadyInitialized();
    error NotInitialized();
    error KeyManagerNotBoundToProfile();

    /// @notice Bind this clone. Called once, by the controller, immediately after `cloneDeterministic`.
    /// @dev Permissionless by design. It cannot be abused because every argument is determined by
    ///      the salt the address was derived from — see the contract-level note. A caller who front-runs
    ///      the controller must supply the same values to land at this address, and any other values
    ///      would have produced a different address.
    function initialize(address _controller, address _profile, bytes32 _credentialId) external {
        if (initialized) revert AlreadyInitialized();
        require(_controller != address(0), "WebAuthn: zero controller");
        require(_profile != address(0), "WebAuthn: zero profile");
        require(_credentialId != bytes32(0), "WebAuthn: zero credential ID");
        controller = IWebAuthnAuthoriser(_controller);
        profile = _profile;
        credentialId = _credentialId;
        initialized = true;
    }

    /// @notice Verify a WebAuthn assertion and execute an ERC725X operation on the profile
    /// @dev The controller reverts unless the assertion is genuine, current and by THIS credential;
    ///      it also refuses any caller that is not this exact proxy, so the nonce cannot be burned
    ///      by anyone else.
    function executeUP(
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data,
        WebAuthn.Assertion memory assertion
    ) external payable returns (bytes memory) {
        if (!initialized) revert NotInitialized();

        address keyManager = _keyManager();
        bytes memory payload = controller.authoriseExecUP(
            profile, credentialId, operationType, target, value, data, assertion
        );
        return ILSP6KeyManagerLike(keyManager).execute{value: msg.value}(payload);
    }

    /// @notice Verify a WebAuthn assertion and write ERC725Y data keys on the profile
    /// @dev The passkey's way to add or change a controller (recovery), anchor a
    ///      credential hash, register an issued asset or edit profile metadata — every write that
    ///      `executeUP` cannot reach. This proxy calls the Key Manager itself, so LSP6 checks THIS
    ///      proxy's permissions for each key. No `msg.sender` check, as for `executeUP`: the
    ///      assertion is the authorisation, so anyone may relay it and the user pays nothing.
    function setDataBatchUP(
        bytes32[] calldata dataKeys,
        bytes[] calldata dataValues,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory) {
        if (!initialized) revert NotInitialized();

        address keyManager = _keyManager();
        bytes memory payload = controller.authoriseSetDataBatchUP(
            profile, credentialId, dataKeys, dataValues, assertion
        );
        return ILSP6KeyManagerLike(keyManager).execute(payload);
    }

    /// @notice Verify ONE WebAuthn assertion and execute an ERC725X `executeBatch` on the profile
    /// @dev Multi-item mints under a single passkey approval. This proxy calls
    ///      the Key Manager, so LSP6 checks THIS proxy's permissions and AllowedCalls for every
    ///      call in the batch; one disallowed call refuses the whole batch. No `msg.sender` check,
    ///      as for `executeUP`. `msg.value` is forwarded; the profile's ERC725X checks the values.
    function executeBatchUP(
        uint256[] calldata operationTypes,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        WebAuthn.Assertion memory assertion
    ) external payable returns (bytes memory) {
        if (!initialized) revert NotInitialized();

        address keyManager = _keyManager();
        bytes memory payload = controller.authoriseExecuteBatchUP(
            profile, credentialId, operationTypes, targets, values, datas, assertion
        );
        return ILSP6KeyManagerLike(keyManager).execute{value: msg.value}(payload);
    }

    /// @notice The Key Manager currently owning this proxy's profile
    /// @dev RESOLVED, NEVER STORED, AND REVERSE-BOUND. `owner()` alone would let a profile name a
    ///      Key Manager that is not bound back to it; `account()` alone would let an attacker-supplied
    ///      Key Manager name any victim. Both directions must agree. Resolving live also means an
    ///      ownership transfer does not strand the proxy — it follows the profile.
    function _keyManager() internal view returns (address resolved) {
        resolved = IOwnable(profile).owner();
        if (resolved == address(0)) revert KeyManagerNotBoundToProfile();
        if (_linkedProfileOf(resolved) != profile) {
            revert KeyManagerNotBoundToProfile();
        }
    }

    /// @dev BOTH GETTERS ARE TRIED. The LSP6 Key Manager from the LUKSO lsp6-contracts package
    ///      0.15 (the version this repo builds against) has no `account()`; its getter is `target()`.
    ///      Older Key Managers and simple mocks expose `account()`. Calling only one of them would
    ///      make `_keyManager()` revert against the other, and the proxy could not act at all.
    ///      Reverse binding is unchanged: whichever getter answers must name this profile.
    function _linkedProfileOf(address keyManager_) internal view returns (address linked) {
        try ILSP6KeyManagerLike(keyManager_).target() returns (address t) {
            return t;
        } catch {}
        try ILSP6KeyManagerLike(keyManager_).account() returns (address a) {
            return a;
        } catch {}
        return address(0);
    }

    /// @notice Public view of the resolved Key Manager, for callers and tests
    function keyManager() external view returns (address) {
        return _keyManager();
    }
}
