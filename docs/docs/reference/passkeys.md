# Passkey contracts

Sources: [`WebAuthnController.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/WebAuthnController.sol), [`WebAuthnSignerProxy.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/WebAuthnSignerProxy.sol), [`WebAuthn.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/WebAuthn.sol), [`P256FallbackVerifier.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/P256FallbackVerifier.sol)

These contracts let a passkey (a WebAuthn credential using the P-256 curve) control a Universal Profile through LSP6, with no private key held by anyone but the device. For the idea in plain language, see [Identities, keys and recovery](/overview/identities#passkeys).

## The model

- **Possession of the key authorises, not a role.** After a profile's first credential is enrolled, every change to its credentials is authorised by a signature from an active credential, or by the profile itself through its Key Manager.
- **Every digest is the WebAuthn challenge.** A passkey signs `sha256(authenticatorData || sha256(clientDataJSON))`, and the challenge lives inside `clientDataJSON`. The contract requires that challenge to equal the operation's own keccak256 digest, which is domain-separated by a message family, `block.chainid`, the controller's address, the profile and a per-credential nonce. A captured assertion cannot be replayed on another chain, another deployment, another operation, or later.
- **One proxy per credential.** Each `(profile, credentialId)` acts through its own `WebAuthnSignerProxy`, an EIP-1167 clone at a CREATE2 address computed by `signerProxyFor`. The proxy is the LSP6 controller, so each passkey has its own permission bitmap, and the Key Manager judges every request against that proxy's permissions.
- **Credential IDs.** On chain, `credentialId = keccak256(rawId)`, where `rawId` is the raw credential ID bytes (`PublicKeyCredential.rawId`). `credentialIdOf(rawId)` computes it.

<figure>
  <img src="/diagrams/passkey-signing.svg" alt="Diagram of the passkey signing path: passkey assertion, any relayer, the credential's signer proxy, WebAuthnController verification, then the profile's Key Manager." />
  <figcaption>The signing path. The relayer carries the assertion and cannot change it.</figcaption>
</figure>

## WebAuthnController

### Credentials

```solidity
function registerCredential(address profile, bytes32 credentialId, uint256 publicKeyX, uint256 publicKeyY, WebAuthn.Assertion memory assertion) external   // profile only, first credential
function enrolCredential(address profile, bytes32 credentialId, uint256 publicKeyX, uint256 publicKeyY, WebAuthn.Assertion memory assertion) external      // profile only, any later credential
function addCredential(address profile, bytes32 authCredentialId, bytes32 newCredentialId, uint256 newPublicKeyX, uint256 newPublicKeyY, WebAuthn.Assertion memory authAssertion, WebAuthn.Assertion memory newKeyAssertion) external
function revokeCredentialByProfile(address profile, bytes32 credentialId) external   // profile only
function retireCredentialGlobally(address profile, bytes32 credentialId) external    // profile only
function revokeCredential(address profile, bytes32 authCredentialId, bytes32 targetCredentialId, WebAuthn.Assertion memory assertion) external   // a credential revoking itself
function getProfileCredentials(address profile) external view returns (bytes32[] memory)
function credentialIdOf(bytes calldata rawId) external pure returns (bytes32)
```

- The first credential is registered by the profile itself (`msg.sender == profile`), and the new key must sign its own enrolment. This happens once per profile and emits `CredentialBootstrapped`.
- Later credentials can be added by the profile through its Key Manager (`enrolCredential`), or by an active credential's signature (`addCredential`). The new key always proves possession of itself.
- **Revocation has two scopes.** `revokeCredentialByProfile` stops a credential on one profile: for when a person leaves an organisation. `retireCredentialGlobally` retires a credential ID and its public key on every profile at once: for a lost or compromised device. A revoked credential can never be enrolled on that profile again; a globally retired one can never be enrolled anywhere.
- The assertion route `revokeCredential` may only revoke the asserting credential itself.
- Revoking the last active credential on a profile is refused (`LastCredentialCannotBeRevoked`), because it would strand the profile.

### Acting for the profile

```solidity
function authoriseExecUP(address profile, bytes32 credentialId, uint256 operationType, address target, uint256 value, bytes calldata data, WebAuthn.Assertion memory assertion) external returns (bytes memory payload)
function authoriseSetDataBatchUP(address profile, bytes32 credentialId, bytes32[] calldata dataKeys, bytes[] calldata dataValues, WebAuthn.Assertion memory assertion) external returns (bytes memory payload)
function authoriseExecuteBatchUP(address profile, bytes32 credentialId, uint256[] calldata operationTypes, address[] calldata targets, uint256[] calldata values, bytes[] calldata datas, WebAuthn.Assertion memory assertion) external returns (bytes memory payload)
```

These are called by the credential's own signer proxy and refuse any other caller. They verify the assertion, spend the nonce, and return the ERC725X or ERC725Y payload. The proxy then sends that payload to the Key Manager itself, so LSP6 checks the **proxy's** permissions: `SETDATA` for ordinary data, `ADDCONTROLLER` to add a key, `EDITPERMISSIONS` to change one.

### Proxies

```solidity
function signerProxyFor(address profile, bytes32 credentialId) public view returns (address)
function deploySignerProxy(address profile, bytes32 credentialId) external returns (address)   // idempotent, anyone may call
function isSignerProxyDeployed(address profile, bytes32 credentialId) external view returns (bool)
```

**Deploy, then grant.** `signerProxyFor` answers before any code exists, so LSP6 permissions could be granted to an address that cannot yet act. Whatever grants the permissions should check `isSignerProxyDeployed` first.

### P-256 verification

```solidity
function verifyP256Signature(bytes32 messageHash, uint256 r, uint256 s, uint256 publicKeyX, uint256 publicKeyY) public view returns (bool)
function supportsP256() public view returns (bool)
function probeP256PrecompileNow() external view returns (bool)
```

The controller uses the RIP-7212 precompile where the chain has one, and `P256FallbackVerifier` where it does not. `supportsP256()` is true on both testnet and mainnet. `probeP256PrecompileNow()` tells them apart: true on testnet, false on mainnet.

### Events

`CredentialRegistered(profile, credentialId, publicKeyX, publicKeyY)`, `CredentialBootstrapped(profile, credentialId, publicKeyX, publicKeyY)`, `CredentialRevoked(profile, credentialId)`, `CredentialRetiredGlobally(profile, credentialId, keyHash)`, `SignerProxyDeployed(profile, credentialId, proxy)`.

### Errors

`InvalidSignature`, `CredentialNotRegistered`, `CredentialAlreadyRegistered`, `P256VerificationFailed`, `AlreadyBootstrapped`, `RelyingPartyMismatch`, `LastCredentialCannotBeRevoked`, `CredentialRetired`, `OnlySelfRevocation`, `CredentialIdBoundToAnotherKey`, `NotThisCredentialsSignerProxy`.

## WebAuthnSignerProxy

```solidity
function executeUP(uint256 operationType, address target, uint256 value, bytes calldata data, WebAuthn.Assertion memory assertion) external payable returns (bytes memory)
function setDataBatchUP(bytes32[] calldata dataKeys, bytes[] calldata dataValues, WebAuthn.Assertion memory assertion) external returns (bytes memory)
function executeBatchUP(uint256[] calldata operationTypes, address[] calldata targets, uint256[] calldata values, bytes[] calldata datas, WebAuthn.Assertion memory assertion) external payable returns (bytes memory)
function keyManager() external view returns (address)
```

Anyone may call these with a valid assertion. The proxy asks the controller to verify it and forwards the returned payload to the profile's Key Manager. A proxy stores nothing that is not derived from its CREATE2 salt, so a front-runner who deploys it lands exactly the same contract.

## The assertion

```solidity
struct Assertion {
    bytes authenticatorData;
    bytes clientDataJSON;
    uint256 typeIndex;       // byte offset of "type":"webauthn.get" in clientDataJSON (a hint, checked)
    uint256 challengeIndex;  // byte offset of "challenge":"..." in clientDataJSON (a hint, checked)
    uint256 r;
    uint256 s;
}
```

## P256FallbackVerifier

```solidity
function verify(bytes32 messageHash, uint256 r, uint256 s, uint256 publicKeyX, uint256 publicKeyY) external view returns (bool)
```

A pure-Solidity P-256 verifier built on the `crypto-lib` (SCL) library vendored in `contracts/lib/crypto-lib`, which includes audit reports from the library's authors under `doc/`. It is reached by address, not imported, because the library cannot compile under `via_ir`. It costs about 218k gas per verification against about 13k with the precompile.

## Versions on chain

| Chain | Controller | Matches this source |
|---|---|---|
| Testnet 4201 | `0xbA2c862f45e7Fcb279F931Ca4ba8EE4c61F9BE81` | Yes (same size as the current source; immutables prevent a byte-for-byte compare) |
| Testnet 4201, earlier, read only | `0xaae14114E369b19697bd6cE97CB578b9f7288454` | No. Kept so clients can find credentials made on it. Nothing signs through it |
| Mainnet 42 | `0xa73bDeA204830B67F9Ab3b38a4aFE4D929067D35` | **No.** An earlier build (11,345 bytes against 15,447 for the current source) |

The mainnet controller predates profile-initiated enrolment (`enrolCredential`), per-profile and global retirement (`revokeCredentialByProfile`, `retireCredentialGlobally`), and the batch and data-write routes (`authoriseSetDataBatchUP`, `authoriseExecuteBatchUP` and the matching proxy functions). Code written against this page should check which functions the deployed controller actually has.

## Tests

The `WebAuthn*.t.sol` and `Passkey*.t.sol` suites, including `PasskeyOrgFlowRealStack.t.sol` against real LSP0 and LSP6 contracts, `WebAuthnClientDigestParity.t.sol` for client and contract digest agreement, and `P256Fallback.t.sol`. `foundry.toml` sets `evm_version = "osaka"` so the test executor has the P-256 precompile and the suite exercises real successful verifications.
