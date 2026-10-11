// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface IWebAuthnProxyDeployer {
    function deploySignerProxy(address profile, bytes32 credentialId)
        external
        returns (address proxy);
    function signerProxyFor(address profile, bytes32 credentialId)
        external
        view
        returns (address);
}

/// @title WebAuthnSignerProxyFactory
/// @notice DEPRECATED. A thin forwarder to `WebAuthnController.deploySignerProxy`.
///
/// @dev WHY IT NO LONGER DEPLOYS ANYTHING ITSELF. The proxy address must be CREATE2-derived from
///      `(profile, credentialId)` with the CONTROLLER as deployer, because `authoriseExecUP`
///      authorises exactly one caller — the address it can recompute. A proxy deployed by a
///      separate factory would land at a different address and could never authorise anything: an
///      inert controller, which is a failure that shows up as a permission grant that succeeded and
///      a user who cannot transact.
///
/// @dev It is kept only for compatibility with `script/DeployWebAuthnSignerProxyFactory.s.sol`
///      and existing integrations. New code should call `WebAuthnController.deploySignerProxy`.
///
/// @dev The old `deployProxy(controller, keyManager, credentialId)` signature is GONE rather than
///      preserved. It took a caller-supplied `keyManager` and bound it into proxy storage — the one
///      value an attacker could choose, and the reason the address was not self-certifying. Keeping
///      it compiling would have been the more dangerous courtesy.
contract WebAuthnSignerProxyFactory {
    /// @notice The `WebAuthnController` that owns proxy deployment
    address public immutable controller;

    event ProxyDeployed(address proxy, address controller, address profile, bytes32 credentialId);

    constructor(address _controller) {
        require(_controller != address(0), "WebAuthn: zero controller");
        controller = _controller;
    }

    /// @notice Deploy the signer proxy for a credential. Idempotent; forwards to the controller.
    function deployProxy(address profile, bytes32 credentialId) external returns (address proxy) {
        proxy = IWebAuthnProxyDeployer(controller).deploySignerProxy(profile, credentialId);
        emit ProxyDeployed(proxy, controller, profile, credentialId);
    }

    /// @notice The address a credential's proxy has, or will have
    function proxyFor(address profile, bytes32 credentialId) external view returns (address) {
        return IWebAuthnProxyDeployer(controller).signerProxyFor(profile, credentialId);
    }
}
