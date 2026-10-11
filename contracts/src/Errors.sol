// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// Centralized custom errors used across the contracts in `src/`.
// Keeping them in one file makes it easy for external tooling and
// client-side parsers to map revert selectors to human-readable names.

// Generic / Registry
error ZeroAddress();
error AssetAlreadyRegistered();
error AssetNotRegistered();
error NotAssetOwner();
error SignerWhitelistedElsewhere();
error SignerNotWhitelisted();
error SignerLinkedElsewhere();
error SignerNotLinked();
error ThresholdInvalid();
error Expired();
error BadSignature();
error NonceMismatch();
error DuplicateSigner();
error ThresholdNotMet();
error CalldataLength();

// Service Provider verifier
error SP_BadCalldata();
error SP_NotActive();
error SP_BadProviderSig();
error SP_Expired();
error SP_NonceUsed();

// Strict policy verifier
error STR_BadCalldata();
error STR_AssetRevoked();
error STR_AssetAlreadyUsed();
error STR_BadAssetSig();
error STR_BadUserSig();
error STR_BadPlatformSig();
error STR_Expired();
error STR_NonceUsed();

// Multi-sig verifier V2
error MSIG_BadCalldata();
error MSIG_Expired();
error MSIG_NonceUsed();
error MSIG_NotActive();
error MSIG_SignerNotLinked();
error MSIG_DuplicateSigner();
error MSIG_ThresholdNotMet();
error MSIG_BadUserSig();

// RealWorldAsset
error RWA_TokenNotMinted();
error RWA_NotTokenOwner();
error RWA_ZeroAddress();
error RWA_SameOwner();
error RWA_NoPendingTransfer();
error RWA_NotPendingOwner();
error RWA_DirectTransferDisabled();
