// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

/**
 * @title ServiceProviderRegistry
 * @notice Tracks approved service providers and per-target activation status.
 * @dev Providers can be toggled by the registry owner; used by `RealWorldAsset` to gate
 *      which addresses can write history events.
 */
contract ServiceProviderRegistry {
    event ProviderStatusSet(address indexed target, address indexed provider, bool active);
    event OwnerChanged(address indexed previous, address indexed current);

    address public owner;
    mapping(address => mapping(address => bool)) private _active; // target => provider => active

    modifier onlyOwner() {
        require(msg.sender == owner, "OWNABLE: not owner");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OWNABLE: zero");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setProviderStatus(address target, address provider, bool active) external onlyOwner {
        _active[target][provider] = active;
        emit ProviderStatusSet(target, provider, active);
    }

    function isActive(address provider, address target) external view returns (bool) {
        return _active[target][provider];
    }
}
