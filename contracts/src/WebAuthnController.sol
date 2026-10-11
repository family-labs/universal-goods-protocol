// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP20CallVerifier as ILSP20} from "@lukso/lsp20-contracts/contracts/ILSP20CallVerifier.sol";
import { ec_isOnCurve } from "@solidity/elliptic/SCL_ecOncurve.sol";
import { a, b, p } from "@solidity/fields/SCL_secp256r1.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {WebAuthn} from "./WebAuthn.sol";
import {IP256Verifier} from "./IP256Verifier.sol";

interface IWebAuthnSignerProxyInit {
    function initialize(address controller, address profile, bytes32 credentialId) external;
}

interface ILSP6KeyManager {
    function execute(bytes calldata payload) external payable returns (bytes memory);
    /// @dev The LSP6 standard getter (`LSP6KeyManagerCore.target`, LUKSO lsp6-contracts 0.15).
    function target() external view returns (address);
    /// @dev The name early Key Managers and this repo's test mocks use.
    function account() external view returns (address);
}

interface IERC725Y {
    function setData(bytes32 dataKey, bytes calldata dataValue) external;
    function owner() external view returns (address);
}

// Minimal interface selector for ERC725X.execute
// bytes4(keccak256("execute(uint256,address,uint256,bytes)")) = 0x44c028fe
bytes4 constant _ERC725X_EXECUTE_SELECTOR = 0x44c028fe;

// bytes4(keccak256("setDataBatch(bytes32[],bytes[])")) = 0x97902421
bytes4 constant _ERC725Y_SET_DATA_BATCH_SELECTOR = 0x97902421;

// bytes4(keccak256("executeBatch(uint256[],address[],uint256[],bytes[])")) = 0x31858452
bytes4 constant _ERC725X_EXECUTE_BATCH_SELECTOR = 0x31858452;

/**
 * @title WebAuthnController
 * @notice LSP20 verifier that validates REAL WebAuthn assertions to control Universal Profiles
 * @dev This contract acts as a proxy to manage universal profiles through key manager permissions
 *      without holding any private keys. It validates credentials using P256 (secp256r1)
 *      signatures instead of traditional secp256k1 ECDSA signatures.
 *
 * Authorisation model: POSSESSION OF THE KEY AUTHORISES, NOT A ROLE.
 * - The FIRST credential for a profile is enrolled by the profile itself (`msg.sender == profile`),
 *   and the key being enrolled must sign its own enrolment (proof of possession). Bootstrap is
 *   once-only per profile and emits a distinct event, so the custody hand-off is auditable on-chain.
 * - EVERY LATER mutation is authorised by an ALREADY-ACTIVE credential's signature, and by
 *   nothing else. There is deliberately no `msg.sender` check on those paths: anyone may RELAY a
 *   signed intent, but only the key holder can produce one. After bootstrap the platform is
 *   structurally out of the loop. That is the whole point of the design.
 * - v2: the PROFILE ITSELF may also add (`enrolCredential`) and revoke
 *   (`revokeCredentialByProfile`) credentials at any time. `msg.sender == profile` means the call
 *   came through the profile's own LSP6 Key Manager from a controller holding CALL there, so the
 *   LSP6 grant is the gate, exactly as for every other action the profile takes. This removes the
 *   dependency on an existing passkey countersigning, which made a lost sole passkey
 *   irreplaceable. The new key still proves possession of itself.
 * - v2: a revoked credential is RETIRED on that profile, permanently. Neither its ID nor its
 *   public key can be enrolled there again, by any path.
 * - v2: retirement has TWO SCOPES.
 *   - PER PROFILE (`revokeCredentialByProfile`, and a credential revoking itself by assertion):
 *     removing an organisation's access. The credential stops on THAT profile only; it keeps
 *     working on every other profile and may still be enrolled on new ones.
 *   - GLOBAL (`retireCredentialGlobally`): the passkey was removed entirely or reported
 *     compromised. Its ID and its public key become unusable on EVERY profile at once (every
 *     signing path refuses them, even where still marked active) and can never be enrolled again.
 * - v2: the assertion route `revokeCredential` may revoke ONLY the asserting
 *   credential itself. Revoking any other credential is a profile decision, made through the
 *   profile's Key Manager by an authorised controller (`revokeCredentialByProfile`).
 *
 * CREDENTIAL ID CONVENTION (v2): the on-chain `bytes32 credentialId` is `keccak256(rawId)`, where
 * `rawId` is the raw WebAuthn credential ID BYTES (`PublicKeyCredential.rawId`, i.e. the base64url
 * `id` decoded, not the base64url string). See `credentialIdOf`. The contract cannot enforce it,
 * because the raw ID never reaches the chain; the server computes it from the verified raw ID, so
 * a stored raw ID links to on-chain state with no second table.
 *
 * Every signed message is domain-separated by a family tag, `block.chainid`, this contract's own
 * address, the profile, and a per-credential nonce, so a signature cannot be replayed across
 * chains, across deployments, across message families, or in time.
 *
 * EVERY DIGEST IS THE WEBAUTHN CHALLENGE.
 * A raw P-256 signature over a `keccak256` digest is not something a real passkey can produce: an
 * authenticator signs `sha256(authenticatorData || sha256(clientDataJSON))`, and the challenge
 * lives INSIDE `clientDataJSON`. So every call site takes a `WebAuthn.Assertion` rather than a
 * bare `(r, s)`, and **each operation's `keccak256` digest is used as the WebAuthn CHALLENGE**.
 * The domain separation, chain binding and nonce discipline of the digests therefore carry over
 * to the assertion unchanged.
 *
 * The check that actually matters is `WebAuthn._requireChallenge` — that the challenge embedded
 * in `clientDataJSON` EQUALS the digest for THIS operation. Without it the contract would verify a
 * genuine assertion over whatever bytes the caller supplied, so an assertion captured from one
 * operation would authorise a different one, and every other test in the suite would still pass.
 */
contract WebAuthnController is ILSP20 {

    /// @notice Emitted when a new credential is registered
    event CredentialRegistered(
        address indexed profile, bytes32 indexed credentialId, uint256 publicKeyX, uint256 publicKeyY
    );

    /// @notice Emitted ONCE per profile, when the first credential is enrolled and custody of the
    ///         profile's authorisation passes from the enroller to the key holder
    event CredentialBootstrapped(
        address indexed profile, bytes32 indexed credentialId, uint256 publicKeyX, uint256 publicKeyY
    );

    /// @notice Emitted when a credential is revoked on ONE profile (per-profile retirement)
    event CredentialRevoked(address indexed profile, bytes32 indexed credentialId);

    /// @notice Emitted when a credential ID and its public key are retired on EVERY profile
    /// @param profile The profile whose Key Manager authorised the global retirement
    event CredentialRetiredGlobally(
        address indexed profile, bytes32 indexed credentialId, bytes32 indexed keyHash
    );

    /// @notice A per-credential signer proxy was deployed
    event SignerProxyDeployed(
        address indexed profile, bytes32 indexed credentialId, address proxy
    );

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when credential is not registered
    error CredentialNotRegistered();

    /// @notice Thrown when attempting to register an already registered credential
    error CredentialAlreadyRegistered();

    /// @notice Thrown when P256 verification fails
    error P256VerificationFailed();

    /// @notice Thrown when a profile that has already bootstrapped attempts to bootstrap again
    error AlreadyBootstrapped();

    /// @notice Thrown when an assertion was produced for a different relying party than the one
    ///         this credential was enrolled under
    error RelyingPartyMismatch();

    /// @notice Thrown when revoking would leave the profile with no active credential at all
    /// @dev Without this guard a key holder can strand their own profile permanently: bootstrap
    ///      is once-only and `bootstrapped[profile]` is never cleared, so there is no way back.
    error LastCredentialCannotBeRevoked();

    /// @notice The credential ID, or its public key, is retired: on this profile (per-profile
    ///         retirement) or on every profile (global retirement)
    /// @dev v2. Retirement is permanent in both scopes: a revoked credential can never be
    ///      silently reactivated where it was retired, whoever asks and however validly they sign.
    ///      A GLOBALLY retired credential is also refused on every signing path, everywhere.
    error CredentialRetired();

    /// @notice The assertion route may only revoke the asserting credential itself
    /// @dev v2. Without this rule, any active credential's assertion could revoke any OTHER
    ///      credential on the profile, so a stolen passkey could race to retire the owner's
    ///      remaining passkeys. Revoking another credential now needs the profile
    ///      route (`revokeCredentialByProfile`), i.e. an authorised controller through LSP6.
    error OnlySelfRevocation();

    /// @notice This credential ID is already bound, on some profile, to a different public key
    /// @dev v2. The guard that makes GLOBAL retirement safe. A credential ID is only
    ///      `keccak256(rawId)`, which the chain cannot tie to a key, so without this anyone could
    ///      register THEIR OWN key under someone else's (public, on-chain) credential ID on a
    ///      profile they control, revoke it there, and so retire the victim's ID everywhere. The
    ///      first registration of an ID binds it to its key (proven by that key's assertion); no
    ///      other key may ever use it.
    error CredentialIdBoundToAnotherKey();

    /// @notice The caller is not the signer proxy this `(profile, credentialId)` derives to
    /// @dev The permission subject at the Key Manager is whoever calls it, so authorising a
    ///      caller other than the credential's own proxy would hand a shared address the user's
    ///      authority — the exact defect the inversion exists to remove.
    error NotThisCredentialsSignerProxy();

    /// @dev Structure to store credential public key
    /// @dev `rpIdHash` is PINNED AT ENROLMENT from the credential's own assertion and never
    ///      written again, so the relying party a key belongs to is fixed by first use, is
    ///      observable on-chain, and cannot be configured by anyone — including the platform.
    struct WebAuthnCredential {
        uint256 publicKeyX;
        uint256 publicKeyY;
        bytes32 rpIdHash;
        bool active;
    }

    /// @dev Mapping from profile address => credentialId => credential data
    mapping(address => mapping(bytes32 => WebAuthnCredential)) public credentials;

    /// @dev Mapping to track registered credential IDs for a profile
    mapping(address => bytes32[]) public profileCredentials;

    /// @dev Per-profile, per-credential nonce. Incremented every time the credential authorises
    ///      something, and folded into the signed message, so no signature is ever valid twice.
    mapping(address => mapping(bytes32 => uint256)) public credentialNonces;

    /// @dev Tombstones (v2, GLOBAL): a credential ID retired by `retireCredentialGlobally` (the
    ///      passkey was removed entirely or reported compromised). Never cleared.
    mapping(bytes32 => bool) public retiredCredentialId;

    /// @dev Tombstones (v2, GLOBAL): `keccak256(abi.encode(x, y))` of a globally retired public
    ///      key, so the same key cannot return anywhere under a fresh ID. Never cleared.
    mapping(bytes32 => bool) public retiredPublicKey;

    /// @dev Tombstones (v2, PER PROFILE): a credential ID revoked on THIS profile (organisation
    ///      access removed, or the credential revoked itself). Never cleared.
    mapping(address => mapping(bytes32 => bool)) public retiredOnProfile;

    /// @dev Tombstones (v2, PER PROFILE): the public key hash of a credential revoked on THIS
    ///      profile, so the same key cannot return here under a fresh ID. Never cleared.
    mapping(address => mapping(bytes32 => bool)) public retiredKeyOnProfile;

    /// @dev The key hash a credential ID was first registered with, on any profile (v2). Zero
    ///      until first use; never cleared. See `CredentialIdBoundToAnotherKey`.
    mapping(bytes32 => bytes32) public credentialIdKey;

    /// @dev Whether a profile has ever enrolled its first credential. Bootstrap is once-only.
    mapping(address => bool) public bootstrapped;

    /// @dev How many credentials are currently ACTIVE for a profile. Backs the last-credential
    ///      guard; `profileCredentials` cannot serve because it never shrinks on revocation.
    mapping(address => uint256) public activeCredentialCount;

    /// @notice Whether this chain answered a KNOWN-VALID P-256 probe at construction
    /// @dev Fixed once, at deployment, because it is a property of the CHAIN and because
    ///      resolving it per-call is impossible: an absent precompile and a bad signature both
    ///      return empty. See `WebAuthn.p256Verify`.
    bool public immutable precompileAvailable;

    /// @notice Pure-Solidity P-256 verifier used where the precompile is absent, or `address(0)`
    /// @dev `immutable`, with NO setter. A mutable verifier address would be a custody hole
    ///      dressed as configuration: whoever could repoint it would decide whether any user's
    ///      signature verifies at all.
    IP256Verifier public immutable p256Fallback;

    /// @notice The `WebAuthnSignerProxy` template every per-credential clone is made from
    /// @dev `immutable`. It is one of the three CREATE2 inputs, so a setter would move every
    ///      user's controller address — silently, and after permissions had been granted to the
    ///      old one.
    address public immutable signerImplementation;

    /// @dev Message family tags. Keep the signed message families disjoint, so a signature
    ///      harvested from one path can never be presented on another.
    bytes32 private constant _TAG_BOOTSTRAP = keccak256("WebAuthnController.bootstrap.v1");
    bytes32 private constant _TAG_ADD = keccak256("WebAuthnController.add.v1");
    bytes32 private constant _TAG_ADD_COUNTERSIGN =
        keccak256("WebAuthnController.addCountersign.v1");
    bytes32 private constant _TAG_REVOKE = keccak256("WebAuthnController.revoke.v1");
    bytes32 private constant _TAG_EXEC = keccak256("WebAuthnController.exec.v1");
    bytes32 private constant _TAG_EXEC_UP = keccak256("WebAuthnController.execUP.v1");
    /// @dev Its own family, so an assertion made to write data can never be
    ///      presented as an `execUP` one, nor the reverse.
    bytes32 private constant _TAG_SET_DATA_UP = keccak256("WebAuthnController.setDataUP.v1");
    /// @dev v2. ERC725X `executeBatch`, for multi-item mints. Its own family, so a
    ///      batch assertion is never an `execUP` or `setDataUP` one, nor the reverse.
    bytes32 private constant _TAG_EXEC_BATCH_UP = keccak256("WebAuthnController.execBatchUP.v1");
    /// @dev v2. A key's proof of possession for a PROFILE-initiated enrolment.
    bytes32 private constant _TAG_ENROL = keccak256("WebAuthnController.enrol.v1");
    bytes32 private constant _TAG_METADATA = keccak256("WebAuthnController.metadata.v1");
    bytes32 private constant _TAG_LSP20 = keccak256("WebAuthnController.lsp20.v1");

    /// @dev Known-VALID P256 vector used to probe whether verification works. Private key = 2, so
    ///      the public key is 2G — whose published coordinates make this a checkable vector.
    ///
    /// IT MUST NOT BE THE PRIVATE-KEY-1 VECTOR.
    /// With private key 1 the public key IS the generator, and the vendored pure-Solidity verifier
    /// REJECTS that case while the precompile accepts it — `SCL_RIP7212.verify` computes
    /// `u*G + v*Q` by Shamir's trick, and `Q == G` collapses its precomputed combinations into
    /// doublings the mixed-addition formula does not handle. Pinned by
    /// `P256FallbackTest.testFallbackRejectsAGeneratorPublicKeyThatThePrecompileAccepts`.
    /// The consequence would be precise and nasty: `supportsP256()` would return FALSE on
    /// exactly the chains that depend on the fallback — LUKSO mainnet — even though the fallback
    /// verifies every REAL credential correctly. A broken instrument reporting a working mechanism
    /// as broken, and the deploy-time gate would have refused the deployment it exists to protect.
    /// No authenticator generates private key 1, so no real credential is affected.
    /// CROSS-CHECKING: `P256FallbackTest.HASH/R/S/PUB_X/PUB_Y` and
    /// `script/lib/P256DeployGate.sol` `PROBE_*` are this same vector. `P256FallbackTest.GEN_X`
    /// (0x6b17d1f2…) is G, the private-key-1 vector this constant was moved AWAY from, kept there
    /// only to pin the divergence; a mismatch against it is expected, not a fault.
    bytes32 private constant _PROBE_HASH =
        0x68418a5367430a8cec56ab6a11907ba494034850f5d5065128fdc3cac0ecd183;
    uint256 private constant _PROBE_R =
        0x748f1832e2aa98358d9afa7debc3766fcf99725fbc7603ee39e60ae17ae17e86;
    uint256 private constant _PROBE_S =
        0x5c7a973262dc6f9665ffece327b9616015910f305e5300cb3910d960ab83342e;
    uint256 private constant _PROBE_PUB_X =
        0x7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978;
    uint256 private constant _PROBE_PUB_Y =
        0x07775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1;

    /// @param fallbackVerifier Pure-Solidity P-256 verifier for chains without the precompile.
    ///        Pass `address(0)` only when deploying to a chain that HAS the precompile — the
    ///        contract will then revert loudly rather than fail silently if that turns out false.
    /// @param signerImplementation_ The `WebAuthnSignerProxy` template every per-credential clone is
    ///        made from. `immutable`: it is one of the three inputs the CREATE2 address depends
    ///        on, so a setter would silently move every user's controller address.
    constructor(IP256Verifier fallbackVerifier, address signerImplementation_) {
        require(signerImplementation_ != address(0), "WebAuthn: zero signer implementation");
        p256Fallback = fallbackVerifier;
        signerImplementation = signerImplementation_;
        precompileAvailable =
            WebAuthn.hasPrecompile(_PROBE_HASH, _PROBE_R, _PROBE_S, _PROBE_PUB_X, _PROBE_PUB_Y);
    }

    /* ========== PER-CREDENTIAL SIGNER PROXIES ========== */

    /// @notice The address of the signer proxy for a credential, deployed or not
    /// @dev THIS FUNCTION IS THE AUTHORISATION. `authoriseExecUP` refuses any caller that is
    ///      not this address, so a proxy can only ever act for the one `(profile, credentialId)`
    ///      its address was derived from. No registry is consulted and none exists — there is
    ///      nothing for the platform to write, and nothing to get out of step.
    ///
    /// @dev THE ADDRESS CANNOT BE OCCUPIED BY DIFFERENT CODE. CREATE2 fixes it as a function of
    ///      `(deployer, salt, initcode)` and all three are pinned: the deployer is THIS contract,
    ///      the salt is `keccak256(abi.encode(profile, credentialId))`, and the initcode is the
    ///      EIP-1167 clone of `signerImplementation`, which is `immutable`. A front-runner who
    ///      deploys here must use the same salt — and `WebAuthnSignerProxy` stores nothing that is
    ///      not derived from that salt, so the contract they land is byte-for-byte ours.
    function signerProxyFor(address profile, bytes32 credentialId)
        public
        view
        returns (address)
    {
        return Clones.predictDeterministicAddress(
            signerImplementation, _proxySalt(profile, credentialId), address(this)
        );
    }

    /// @notice Deploy the signer proxy for a credential. Idempotent, permissionless.
    ///
    /// @dev THE COUNTERFACTUAL-ADDRESS HAZARD, AND THE ORDERING THAT CLOSES IT.
    ///      `signerProxyFor` answers before any code exists there, so LSP6 permissions CAN be
    ///      granted to an address that cannot act — an inert-controller failure which no revert
    ///      and no bitmap read detects, because the grant succeeds
    ///      and the profile looks correctly configured.
    ///
    ///      THE ORDERING IS: DEPLOY, THEN GRANT. This function is idempotent and open to anyone,
    ///      so the deploying step can never be the thing that blocks; `isSignerProxyDeployed` makes
    ///      the precondition checkable before a grant rather than discoverable afterwards.
    ///      The ordering cannot be ENFORCED from here — granting permissions is a `setData` on
    ///      the profile, which this contract neither performs nor observes. It is stated, tested,
    ///      and must be honoured by whatever performs the grant.
    function deploySignerProxy(address profile, bytes32 credentialId)
        external
        returns (address proxy)
    {
        require(profile != address(0), "WebAuthn: zero profile address");
        require(credentialId != bytes32(0), "WebAuthn: zero credential ID");

        proxy = signerProxyFor(profile, credentialId);
        if (proxy.code.length != 0) return proxy;

        Clones.cloneDeterministic(signerImplementation, _proxySalt(profile, credentialId));
        IWebAuthnSignerProxyInit(proxy).initialize(address(this), profile, credentialId);
        emit SignerProxyDeployed(profile, credentialId, proxy);
    }

    /// @notice Whether the signer proxy for a credential has code
    /// @dev Exists so the precondition for a permission grant is a question that can be ASKED.
    function isSignerProxyDeployed(address profile, bytes32 credentialId)
        external
        view
        returns (bool)
    {
        return signerProxyFor(profile, credentialId).code.length != 0;
    }

    function _proxySalt(address profile, bytes32 credentialId) internal pure returns (bytes32) {
        return keccak256(abi.encode(profile, credentialId));
    }

    /// @notice Verify an assertion and return the ERC725X payload for the caller to forward
    ///
    /// @dev THE INVERSION. This function does NOT call the Key Manager. Its caller does — and
    ///      its caller is a per-credential proxy, so `LSP6KeyManagerCore._execute` (`:420`) verifies
    ///      the permissions of THAT address rather than of this shared contract. Everything else is
    ///      `executeUPViaKeyManager` unchanged, including the digest, byte for byte, so no client
    ///      or assertion has to change.
    ///
    /// @dev THE CALLER CHECK IS NOT HOUSEKEEPING. Without it any address could burn a
    ///      credential's nonce — the counter every signed message depends on — and could obtain a
    ///      payload authorised by an assertion it merely relayed.
    function authoriseExecUP(
        address profile,
        bytes32 credentialId,
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload) {
        if (msg.sender != signerProxyFor(profile, credentialId)) {
            revert NotThisCredentialsSignerProxy();
        }

        WebAuthnCredential storage cred = credentials[profile][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(profile, credentialId);
        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_EXEC_UP,
                block.chainid,
                address(this),
                profile,
                credentialId,
                nonce,
                operationType,
                target,
                value,
                keccak256(data)
            )
        );
        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        payload = abi.encodeWithSelector(
            _ERC725X_EXECUTE_SELECTOR, operationType, target, value, data
        );
    }

    /// @notice Verify an assertion and return an ERC725Y `setDataBatch` payload for THIS credential's
    ///         proxy to send to the Key Manager.
    /// @dev THE DATA-WRITE TRANSPORT. Without this function a passkey could hold
    ///      ADDCONTROLLER + EDITPERMISSIONS and never use them: `authoriseExecUP` only ever returns an
    ///      ERC725X `execute` payload, and the self-call route to `setData` would make the PROFILE the
    ///      LSP6 permission subject (rejected: it lets a scoped delegate escalate). Returning a
    ///      `setDataBatch` payload that the proxy sends DIRECTLY keeps the PROXY as the subject, so
    ///      LSP6 judges every key against that proxy's own bitmap — ordinary data needs SETDATA, a
    ///      new controller needs ADDCONTROLLER, a changed one needs EDITPERMISSIONS
    ///      (`LSP6SetDataModule`). Proven against the real LSP0/LSP6 in
    ///      `test/PasskeySetDataViaProxy.t.sol` and `test/WebAuthnSetDataUP.t.sol`.
    /// @dev Same discipline as `authoriseExecUP`: only this credential's own proxy may call, the
    ///      nonce is consumed before verification can succeed, and the digest binds the exact keys
    ///      and values, so an assertion for one write cannot authorise another.
    function authoriseSetDataBatchUP(
        address profile,
        bytes32 credentialId,
        bytes32[] calldata dataKeys,
        bytes[] calldata dataValues,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload) {
        if (msg.sender != signerProxyFor(profile, credentialId)) {
            revert NotThisCredentialsSignerProxy();
        }
        require(dataKeys.length == dataValues.length, "WebAuthn: keys/values length mismatch");
        require(dataKeys.length > 0, "WebAuthn: nothing to write");

        WebAuthnCredential storage cred = credentials[profile][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(profile, credentialId);
        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_SET_DATA_UP,
                block.chainid,
                address(this),
                profile,
                credentialId,
                nonce,
                keccak256(abi.encode(dataKeys, dataValues))
            )
        );
        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        payload = abi.encodeWithSelector(_ERC725Y_SET_DATA_BATCH_SELECTOR, dataKeys, dataValues);
    }

    /// @notice Verify an assertion and return an ERC725X `executeBatch` payload for THIS
    ///         credential's proxy to send to the Key Manager: several calls, one approval.
    /// @dev v2: the passkey route for multi-item mints. LSP6 verifies EACH call in
    ///      an `executeBatch` against the caller's permissions and AllowedCalls
    ///      (`LSP6KeyManagerCore._verifyPermissions`), and the caller is the proxy, so a batch can do
    ///      nothing the proxy could not do call by call.
    /// @dev The digest binds all four arrays IN ORDER, through
    ///      `keccak256(abi.encode(operationTypes, targets, values, datas))`, so no element can be
    ///      changed, reordered, added or dropped. Same proxy-only caller and nonce discipline as
    ///      `authoriseExecUP`.
    ///      Challenge = keccak256(abi.encode(keccak256("WebAuthnController.execBatchUP.v1"),
    ///        chainId, controller, profile, credentialId, nonce,
    ///        keccak256(abi.encode(operationTypes, targets, values, datas)))).
    function authoriseExecuteBatchUP(
        address profile,
        bytes32 credentialId,
        uint256[] calldata operationTypes,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory payload) {
        if (msg.sender != signerProxyFor(profile, credentialId)) {
            revert NotThisCredentialsSignerProxy();
        }
        require(
            operationTypes.length == targets.length && targets.length == values.length
                && values.length == datas.length,
            "WebAuthn: batch length mismatch"
        );
        require(targets.length > 0, "WebAuthn: empty batch");

        WebAuthnCredential storage cred = credentials[profile][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(profile, credentialId);
        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_EXEC_BATCH_UP,
                block.chainid,
                address(this),
                profile,
                credentialId,
                nonce,
                keccak256(abi.encode(operationTypes, targets, values, datas))
            )
        );
        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        payload = abi.encodeWithSelector(
            _ERC725X_EXECUTE_BATCH_SELECTOR, operationTypes, targets, values, datas
        );
    }

    /// @dev The honest LSP6 path arrives here AS THE UNIVERSAL PROFILE, never as the Key Manager:
    ///      LSP6KeyManagerCore._execute forwards to _target. So `msg.sender == profile` is the
    ///      reachable guard, and `msg.sender == keyManager` is a value that cannot occur.
    modifier onlyProfile(address profile) {
        require(profile != address(0), "WebAuthn: zero profile address");
        require(msg.sender == profile, "WebAuthn: caller not profile");
        _;
    }

    /* ========== ENROLMENT ========== */

    /// @notice Enrol the FIRST credential for a profile. Once only, per profile.
    /// @dev Authorised two ways at once, and it needs both:
    ///      (1) `msg.sender == profile` — only the profile may open its own account; and
    ///      (2) the enrolled key signs its own enrolment as a WebAuthn assertion, so the enroller
    ///          must actually hold the passkey and cannot bind a key it does not control.
    ///      Deliberately NOT gated on the Key Manager or an owner role. On a relayer-managed profile the
    ///      owner is the LSP6 Key Manager whose only controller is the platform's relayer, so an
    ///      owner gate would mean "only the platform may enrol a passkey" — custody, re-asserted.
    /// @param profile The Universal Profile (or EOA acting for itself) the credential is bound to
    /// @param credentialId The credential ID (hash of credential)
    /// @param publicKeyX The X coordinate of the P256 public key
    /// @param publicKeyY The Y coordinate of the P256 public key
    /// @param assertion A WebAuthn assertion by the key being enrolled, over the bootstrap digest
    function registerCredential(
        address profile,
        bytes32 credentialId,
        uint256 publicKeyX,
        uint256 publicKeyY,
        WebAuthn.Assertion memory assertion
    ) external onlyProfile(profile) {
        if (bootstrapped[profile]) revert AlreadyBootstrapped();
        require(credentialId != bytes32(0), "WebAuthn: zero credential ID");
        require(ec_isOnCurve(p, a, b, publicKeyX, publicKeyY), "WebAuthn: invalid public key");
        _requireNotRetired(profile, credentialId, publicKeyX, publicKeyY);

        WebAuthnCredential storage cred = credentials[profile][credentialId];
        if (cred.active) revert CredentialAlreadyRegistered();

        bytes32 digest = keccak256(
            abi.encode(
                _TAG_BOOTSTRAP,
                block.chainid,
                address(this),
                profile,
                credentialId,
                publicKeyX,
                publicKeyY,
                uint256(0)
            )
        );
        if (!_verify(digest, assertion, publicKeyX, publicKeyY)) revert InvalidSignature();

        // The relying party is pinned from the enrolling assertion itself — never configured.
        _store(profile, credentialId, publicKeyX, publicKeyY, WebAuthn.rpIdHash(assertion));
        bootstrapped[profile] = true;

        emit CredentialBootstrapped(profile, credentialId, publicKeyX, publicKeyY);
        emit CredentialRegistered(profile, credentialId, publicKeyX, publicKeyY);
    }

    /// @notice Add a further credential, authorised by an ALREADY-ACTIVE credential's assertion
    ///         AND counter-signed by the key being added
    /// @dev There is NO `msg.sender` check here, and that is the design. Anyone may relay a
    ///      signed intent; only the key holder can produce one. This is what makes rotation
    ///      self-sovereign — the platform cannot add a key, and cannot stop the user adding one.
    /// @dev THE COUNTER-SIGNATURE IS NOT CEREMONY. Without it an active credential can bind a
    ///      public key whose private half nobody present has ever demonstrated — a typo, a
    ///      substituted key, or a key chosen by whoever built the calldata — and the profile would
    ///      carry a credential its supposed holder cannot use and did not consent to.
    /// @param profile The profile the credentials belong to
    /// @param authCredentialId An active credential authorising this addition
    /// @param newCredentialId The credential ID being added
    /// @param newPublicKeyX The X coordinate of the new P256 public key
    /// @param newPublicKeyY The Y coordinate of the new P256 public key
    /// @param authAssertion Assertion by `authCredentialId` over the add digest
    /// @param newKeyAssertion Assertion by the NEW key over the counter-signature digest
    function addCredential(
        address profile,
        bytes32 authCredentialId,
        bytes32 newCredentialId,
        uint256 newPublicKeyX,
        uint256 newPublicKeyY,
        WebAuthn.Assertion memory authAssertion,
        WebAuthn.Assertion memory newKeyAssertion
    ) external {
        require(profile != address(0), "WebAuthn: zero profile address");
        require(newCredentialId != bytes32(0), "WebAuthn: zero credential ID");
        require(
            ec_isOnCurve(p, a, b, newPublicKeyX, newPublicKeyY), "WebAuthn: invalid public key"
        );

        WebAuthnCredential storage auth = credentials[profile][authCredentialId];
        _requireUsable(auth, authCredentialId);
        if (credentials[profile][newCredentialId].active) revert CredentialAlreadyRegistered();
        _requireNotRetired(profile, newCredentialId, newPublicKeyX, newPublicKeyY);

        uint256 nonce = _useNonce(profile, authCredentialId);

        bytes32 digest = keccak256(
            abi.encode(
                _TAG_ADD,
                block.chainid,
                address(this),
                profile,
                authCredentialId,
                nonce,
                newCredentialId,
                newPublicKeyX,
                newPublicKeyY
            )
        );
        if (!_verifyBy(auth, digest, authAssertion)) revert InvalidSignature();

        // Proof of possession of the key being added, over the SAME nonce so both halves are
        //    bound to this one operation and neither can be lifted onto another.
        bytes32 counterDigest = keccak256(
            abi.encode(
                _TAG_ADD_COUNTERSIGN,
                block.chainid,
                address(this),
                profile,
                authCredentialId,
                nonce,
                newCredentialId,
                newPublicKeyX,
                newPublicKeyY
            )
        );
        if (!_verify(counterDigest, newKeyAssertion, newPublicKeyX, newPublicKeyY)) {
            revert InvalidSignature();
        }

        _store(
            profile,
            newCredentialId,
            newPublicKeyX,
            newPublicKeyY,
            WebAuthn.rpIdHash(newKeyAssertion)
        );
        emit CredentialRegistered(profile, newCredentialId, newPublicKeyX, newPublicKeyY);
    }

    /// @notice Enrol a credential on the PROFILE's own authority, at any time (v2)
    /// @dev `msg.sender == profile` is the authorisation: the call reached here through the
    ///      profile's LSP6 Key Manager, from a controller holding CALL (or an AllowedCall to this
    ///      contract) on it, typically the browser key. The LSP6 grant is the real gate. No
    ///      existing passkey has to countersign, so a profile whose only passkey is lost can still
    ///      enrol a replacement. Not once-only, unlike `registerCredential`; if it is the profile's
    ///      first credential it also marks the profile bootstrapped.
    /// @dev Proof of possession is kept: the NEW key signs its own enrolment, and its relying
    ///      party is pinned from that assertion. No nonce is needed: the digest binds the ID and the
    ///      key, an active ID is refused and a retired one is refused forever, so a replay can
    ///      never enrol anything a second time.
    ///      Challenge = keccak256(abi.encode(keccak256("WebAuthnController.enrol.v1"), chainId,
    ///        controller, profile, credentialId, publicKeyX, publicKeyY)).
    /// @param credentialId `keccak256(rawId)`; see the contract-level convention and `credentialIdOf`
    function enrolCredential(
        address profile,
        bytes32 credentialId,
        uint256 publicKeyX,
        uint256 publicKeyY,
        WebAuthn.Assertion memory assertion
    ) external onlyProfile(profile) {
        require(credentialId != bytes32(0), "WebAuthn: zero credential ID");
        require(ec_isOnCurve(p, a, b, publicKeyX, publicKeyY), "WebAuthn: invalid public key");
        if (credentials[profile][credentialId].active) revert CredentialAlreadyRegistered();
        _requireNotRetired(profile, credentialId, publicKeyX, publicKeyY);

        bytes32 digest = keccak256(
            abi.encode(
                _TAG_ENROL,
                block.chainid,
                address(this),
                profile,
                credentialId,
                publicKeyX,
                publicKeyY
            )
        );
        if (!_verify(digest, assertion, publicKeyX, publicKeyY)) revert InvalidSignature();

        _store(profile, credentialId, publicKeyX, publicKeyY, WebAuthn.rpIdHash(assertion));
        if (!bootstrapped[profile]) {
            bootstrapped[profile] = true;
            emit CredentialBootstrapped(profile, credentialId, publicKeyX, publicKeyY);
        }
        emit CredentialRegistered(profile, credentialId, publicKeyX, publicKeyY);
    }

    /// @notice Revoke ANY active credential on the PROFILE's own authority, including the last
    ///         (v2). Retires it on THIS PROFILE ONLY.
    /// @dev Same gate as `enrolCredential`: only the profile, i.e. through its LSP6 Key Manager.
    ///      The last credential may go: the profile can always enrol another through LSP6, and a
    ///      compromised sole passkey must be removable.
    /// @dev PER-PROFILE SCOPE. This is what removing an organisation's access
    ///      (and removing a member) calls, so it must not touch the person's other profiles: the
    ///      credential keeps signing wherever else it is active, and may still be enrolled on NEW
    ///      profiles. Its ID and key are tombstoned HERE, permanently. Global retirement is the
    ///      separate, explicit `retireCredentialGlobally`.
    /// @dev This deactivates the credential at the controller, so its proxy can no longer obtain
    ///      a payload. Zeroing the proxy's LSP6 AddressPermissions is a separate, also sufficient,
    ///      revocation; doing both is the complete one.
    function revokeCredentialByProfile(address profile, bytes32 credentialId)
        external
        onlyProfile(profile)
    {
        WebAuthnCredential storage target = credentials[profile][credentialId];
        if (!target.active) revert CredentialNotRegistered();
        _retireOnProfile(profile, credentialId, target);
    }

    /// @notice Retire a credential's ID AND public key on EVERY profile, on the profile's own
    ///         authority (v2). For a passkey removed entirely, or reported compromised.
    /// @dev Gate: `msg.sender == profile` (through its LSP6 Key Manager, CALL), AND the credential
    ///      must have been registered on this profile at some point (it may already be revoked
    ///      here). Registration on any profile needed an assertion by the key itself, so a profile
    ///      can only retire a credential whose holder enrolled it there.
    /// @dev ANTI-GRIEFING, kept from the global-retirement design: the first registration of an
    ///      ID binds it to its key (`credentialIdKey`), and every later registration with another
    ///      key is refused. So the `(id, key)` pair recorded on this profile is the genuine one,
    ///      and nobody can retire someone else's ID by registering their own key under it.
    /// @dev Effects: deactivates the credential here if it is active (and tombstones it here);
    ///      sets the global tombstones for the ID and the key. From then on every signing path
    ///      refuses the credential on every profile (`_requireUsable`), even where it is still
    ///      marked active, and no profile can enrol the ID or the key again. Reverts with
    ///      `CredentialRetired` when there is nothing left to do, so a retry is never silent.
    function retireCredentialGlobally(address profile, bytes32 credentialId)
        external
        onlyProfile(profile)
    {
        WebAuthnCredential storage target = credentials[profile][credentialId];
        if (target.publicKeyX == 0 && target.publicKeyY == 0) revert CredentialNotRegistered();
        bytes32 keyHash = _keyHash(target.publicKeyX, target.publicKeyY);
        bool alreadyGlobal = retiredCredentialId[credentialId] && retiredPublicKey[keyHash];
        if (!target.active && alreadyGlobal) revert CredentialRetired();

        if (target.active) _retireOnProfile(profile, credentialId, target);
        if (!alreadyGlobal) {
            retiredCredentialId[credentialId] = true;
            retiredPublicKey[keyHash] = true;
            emit CredentialRetiredGlobally(profile, credentialId, keyHash);
        }
    }

    /// @notice The on-chain credential ID for a raw WebAuthn credential ID: `keccak256(rawId)`
    /// @dev The convention every enrolment path expects (not enforceable on chain: the raw ID
    ///      is never submitted). Exposed so the server and client can check their derivation.
    function credentialIdOf(bytes calldata rawId) external pure returns (bytes32) {
        return keccak256(rawId);
    }

    /// @notice A credential revokes ITSELF on this profile, authorised by its own assertion
    /// @dev Same self-sovereign rule as `addCredential`: no `msg.sender` check, signature only.
    /// @dev v2: ONLY ITSELF. `targetCredentialId` must equal
    ///      `authCredentialId`, otherwise `OnlySelfRevocation`. Revoking any OTHER credential is a
    ///      profile decision, made through the profile's Key Manager by an authorised controller
    ///      (`revokeCredentialByProfile`). This closes the race in which a stolen passkey retires
    ///      the owner's other passkeys. The parameter is kept so the ABI and the signed digest
    ///      are unchanged.
    /// @dev DESIGN (v2): the last-credential guard STAYS on this path. Removing a
    ///      profile's last passkey is a profile-level decision, so it goes through LSP6 via
    ///      `revokeCredentialByProfile`, where the profile's own controllers decide. A passkey
    ///      alone (or whoever relays its assertion) cannot leave the profile with none. The
    ///      credential is retired on THIS profile only, as on the profile path.
    /// @param profile The profile the credential belongs to
    /// @param authCredentialId The active credential revoking itself
    /// @param targetCredentialId Must equal `authCredentialId`
    /// @param assertion Assertion by `authCredentialId` over the revoke digest
    function revokeCredential(
        address profile,
        bytes32 authCredentialId,
        bytes32 targetCredentialId,
        WebAuthn.Assertion memory assertion
    ) external {
        if (targetCredentialId != authCredentialId) revert OnlySelfRevocation();

        WebAuthnCredential storage auth = credentials[profile][authCredentialId];
        _requireUsable(auth, authCredentialId);
        WebAuthnCredential storage target = auth;

        // Checked BEFORE the nonce is consumed, so a refused revocation does not silently
        //    invalidate the caller's other outstanding signatures.
        if (activeCredentialCount[profile] <= 1) revert LastCredentialCannotBeRevoked();

        uint256 nonce = _useNonce(profile, authCredentialId);
        bytes32 digest = keccak256(
            abi.encode(
                _TAG_REVOKE,
                block.chainid,
                address(this),
                profile,
                authCredentialId,
                nonce,
                targetCredentialId
            )
        );
        if (!_verifyBy(auth, digest, assertion)) revert InvalidSignature();

        _retireOnProfile(profile, targetCredentialId, target);
    }

    /// @notice Get all credential IDs for a profile
    /// @dev This list NEVER shrinks — a revoked credential stays in it. Use
    ///      `credentials(profile, id).active` or `activeCredentialCount` to ask what is live.
    /// @param profile The Universal Profile address
    /// @return Array of credential IDs
    function getProfileCredentials(address profile) external view returns (bytes32[] memory) {
        return profileCredentials[profile];
    }

    /* ========== P256 VERIFICATION ========== */

    /// @notice Verify a raw P-256 signature over a hash, by whichever path this deployment uses
    /// @dev This is the RAW curve operation and is exposed for testing and inspection only. It is
    ///      NOT the authorisation path: nothing a passkey produces is a signature over a bare hash.
    ///      `WebAuthn.verify` is what this contract actually authorises with.
    function verifyP256Signature(
        bytes32 messageHash,
        uint256 r,
        uint256 s,
        uint256 publicKeyX,
        uint256 publicKeyY
    ) public view returns (bool) {
        return WebAuthn.p256Verify(
            messageHash, r, s, publicKeyX, publicKeyY, precompileAvailable, p256Fallback
        );
    }

    /// @notice Whether this deployment can verify P-256 signatures AT ALL, by any path
    /// @dev This is not the same question as "does the chain have the precompile" — a
    ///      deployment with a fallback verifier answers true on a chain without it.
    function supportsP256() public view returns (bool) {
        return verifyP256Signature(_PROBE_HASH, _PROBE_R, _PROBE_S, _PROBE_PUB_X, _PROBE_PUB_Y);
    }

    /// @notice Re-probe the precompile LIVE, rather than reading the value fixed at construction
    /// @dev Exists so that a stale `precompileAvailable` is OBSERVABLE. A chain can gain the
    ///      precompile in a hard fork after this contract was deployed; the immutable would then
    ///      read false forever and the contract would keep paying for the fallback. That is a
    ///      cost bug, never a correctness one — but it should not be invisible.
    function probeP256PrecompileNow() external view returns (bool) {
        return WebAuthn.hasPrecompile(_PROBE_HASH, _PROBE_R, _PROBE_S, _PROBE_PUB_X, _PROBE_PUB_Y);
    }

    /* ========== LSP20 ========== */

    /// @notice LSP20 verification function called before operation execution
    /// @dev REPLAY: `ILSP20.lsp20VerifyCall` is `view`, so this path CANNOT consume a nonce.
    ///      The digest binds the family tag, `block.chainid`, this contract, the target and the
    ///      credential's CURRENT nonce — so it is safe across chains and deployments, and any
    ///      nonce advance on another path invalidates outstanding signatures. Same-chain replay
    ///      while the nonce is unchanged remains open and cannot be closed behind a `view`
    ///      interface. Recorded rather than hidden.
    /// @dev CALLDATA LAYOUT. A WebAuthn assertion is variable-length, so a fixed 96-byte tail
    ///      (`credentialId || r || s`) cannot carry it. The layout is
    ///      `originalCallData || abi.encode(credentialId, assertion) || uint256(blobLength)`,
    ///      with the length LAST so it can be found without knowing anything else first.
    /// @param requestor The address requesting the operation
    /// @param target The target Universal Profile
    /// @param caller The actual caller (may differ from requestor)
    /// @param value The value being sent
    /// @param callData The calldata for the operation, with the assertion blob appended
    /// @return magicValue The LSP20 magic value indicating verification result
    function lsp20VerifyCall(
        address requestor,
        address target,
        address caller,
        uint256 value,
        bytes memory callData
    ) external view override returns (bytes4) {
        // Silence unused parameter warnings
        requestor;
        caller;
        value;

        require(target != address(0), "WebAuthn: zero target");
        require(callData.length >= 4, "WebAuthn: invalid calldata");
        require(callData.length >= 32, "WebAuthn: calldata too short");

        uint256 dataLength = callData.length;
        uint256 blobLength;
        assembly {
            blobLength := mload(add(callData, dataLength))
        }
        // `blobLength` is attacker-controlled; compare without adding, so it cannot overflow
        //    into a passing comparison.
        require(blobLength <= dataLength - 32, "WebAuthn: calldata too short");

        uint256 contentLength = dataLength - 32 - blobLength;
        bytes memory blob = _slice(callData, contentLength, blobLength);

        (bytes32 credentialId, WebAuthn.Assertion memory assertion) =
            abi.decode(blob, (bytes32, WebAuthn.Assertion));

        WebAuthnCredential storage cred = credentials[target][credentialId];
        _requireUsable(cred, credentialId);

        bytes32 opHash;
        assembly {
            opHash := keccak256(add(callData, 0x20), contentLength)
        }

        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_LSP20,
                block.chainid,
                address(this),
                target,
                credentialId,
                credentialNonces[target][credentialId],
                opHash
            )
        );

        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        // Return success magic value (no post-verification needed)
        return _ok(false);
    }

    /// @notice LSP20 post-verification (not used)
    function lsp20VerifyCallResult(bytes32, /*callHash*/ bytes memory /*callResult*/ )
        external
        pure
        override
        returns (bytes4)
    {
        return ILSP20.lsp20VerifyCallResult.selector;
    }

    /// @dev Helper to construct LSP20 magic value
    function _ok(bool verifyAfter) internal pure returns (bytes4) {
        return bytes4(
            bytes.concat(
                bytes3(ILSP20.lsp20VerifyCall.selector), verifyAfter ? bytes1(0x01) : bytes1(0x00)
            )
        );
    }

    /* ========== KEY MANAGER FORWARDING ========== */

    /// @notice Verify a WebAuthn assertion and forward payload to the LSP6 Key Manager
    /// @param keyManager Address of the LSP6 Key Manager linked to the Universal Profile
    /// @param payload Encoded call to be executed by the Key Manager (e.g., UP.setData(...))
    /// @param credentialId Registered credential ID
    /// @param assertion Assertion by `credentialId` over the exec digest
    /// @return result Raw bytes returned by the Key Manager execution
    function executeViaKeyManager(
        address keyManager,
        bytes calldata payload,
        bytes32 credentialId,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory result) {
        address upAccount = _resolveProfile(keyManager);

        WebAuthnCredential storage cred = credentials[upAccount][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(upAccount, credentialId);
        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_EXEC,
                block.chainid,
                address(this),
                upAccount,
                credentialId,
                nonce,
                keccak256(payload)
            )
        );
        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        return ILSP6KeyManager(keyManager).execute(payload);
    }

    /// @notice Verify a WebAuthn assertion and forward an ERC725X `execute(...)` call via LSP6
    /// @param keyManager Address of the LSP6 Key Manager linked to the Universal Profile
    /// @param operationType The ERC725X operation type (CALL=0, CREATE=1, CREATE2=2, STATICCALL=3, DELEGATECALL=4)
    /// @param target The address to call (or unused for CREATE/CREATE2)
    /// @param value Native token amount to transfer (Wei)
    /// @param data ABI-encoded call data or contract creation bytecode
    /// @param credentialId Registered credential ID
    /// @param assertion Assertion by `credentialId` over the execUP digest
    /// @return result Raw bytes returned by the Key Manager execution
    function executeUPViaKeyManager(
        address keyManager,
        uint256 operationType,
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 credentialId,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes memory result) {
        address upAccount = _resolveProfile(keyManager);

        WebAuthnCredential storage cred = credentials[upAccount][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(upAccount, credentialId);
        bytes32 messageHash = keccak256(
            abi.encode(
                _TAG_EXEC_UP,
                block.chainid,
                address(this),
                upAccount,
                credentialId,
                nonce,
                operationType,
                target,
                value,
                keccak256(data)
            )
        );
        if (!_verifyBy(cred, messageHash, assertion)) revert InvalidSignature();

        bytes memory payload = abi.encodeWithSelector(
            _ERC725X_EXECUTE_SELECTOR, operationType, target, value, data
        );
        return ILSP6KeyManager(keyManager).execute(payload);
    }

    /// @notice Store credential metadata on the Universal Profile via its Key Manager (ERC725Y)
    /// @dev The credential must sign for its own metadata write. Without that, any address could
    ///      advance the persistent nonce the signed messages depend on.
    /// @param keyManager The LSP6 Key Manager address controlling the Universal Profile
    /// @param credentialId The credential to store metadata for
    /// @param assertion Assertion by `credentialId` over the metadata digest
    /// @return dataKey The ERC725Y key used for metadata storage
    function storeCredentialMetadataViaKeyManager(
        address keyManager,
        bytes32 credentialId,
        WebAuthn.Assertion memory assertion
    ) external returns (bytes32 dataKey) {
        address profile = _resolveProfile(keyManager);

        WebAuthnCredential storage cred = credentials[profile][credentialId];
        _requireUsable(cred, credentialId);

        uint256 nonce = _useNonce(profile, credentialId);
        bytes32 digest = keccak256(
            abi.encode(
                _TAG_METADATA, block.chainid, address(this), profile, credentialId, nonce
            )
        );
        if (!_verifyBy(cred, digest, assertion)) revert InvalidSignature();

        dataKey = keccak256(abi.encodePacked("WebAuthnCredential:", credentialId));
        bytes memory dataValue = abi.encode(cred.publicKeyX, cred.publicKeyY, nonce + 1);

        bytes memory payload = abi.encodeWithSignature("setData(bytes32,bytes)", dataKey, dataValue);
        ILSP6KeyManager(keyManager).execute(payload);
    }

    /* ========== INTERNAL ========== */

    /// @dev Verify an assertion by an ALREADY-ENROLLED credential, enforcing the relying party
    ///      pinned when that credential was enrolled.
    function _verifyBy(
        WebAuthnCredential storage cred,
        bytes32 challenge,
        WebAuthn.Assertion memory assertion
    ) internal view returns (bool) {
        if (WebAuthn.rpIdHash(assertion) != cred.rpIdHash) revert RelyingPartyMismatch();
        return _verify(challenge, assertion, cred.publicKeyX, cred.publicKeyY);
    }

    /// @dev Verify an assertion against a public key given explicitly — used where the credential
    ///      is not yet enrolled and so has no pinned relying party (bootstrap, counter-signature).
    function _verify(
        bytes32 challenge,
        WebAuthn.Assertion memory assertion,
        uint256 publicKeyX,
        uint256 publicKeyY
    ) internal view returns (bool) {
        return WebAuthn.verify(
            challenge, assertion, publicKeyX, publicKeyY, precompileAvailable, p256Fallback
        );
    }

    /// @dev Copy `length` bytes out of `data` starting at `start`.
    function _slice(bytes memory data, uint256 start, uint256 length)
        internal
        pure
        returns (bytes memory out)
    {
        out = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = data[start + i];
        }
    }

    /// @dev Resolve the profile behind a Key Manager, with REVERSE BINDING.
    ///      `keyManager` is caller-supplied, so `account()` alone proves nothing: a fake Key
    ///      Manager can return any victim's address. The profile must name the SAME Key Manager
    ///      as its owner for the pair to be believed.
    /// @dev The real LSP6 Key Manager exposes `target()`, not `account()`, so calling only
    ///      `account()` would make every `*ViaKeyManager` function revert against a real profile.
    ///      As in `WebAuthnSignerProxy._linkedProfileOf`: try `target()`, then `account()`. The
    ///      reverse-binding check below is unchanged.
    function _resolveProfile(address keyManager) internal view returns (address profile) {
        require(keyManager != address(0), "WebAuthn: zero keyManager");
        profile = _linkedProfileOf(keyManager);
        require(profile != address(0), "WebAuthn: invalid KM account");
        require(IERC725Y(profile).owner() == keyManager, "WebAuthn: KM not profile owner");
    }

    function _linkedProfileOf(address keyManager) internal view returns (address linked) {
        try ILSP6KeyManager(keyManager).target() returns (address t) {
            return t;
        } catch {}
        try ILSP6KeyManager(keyManager).account() returns (address a) {
            return a;
        } catch {}
        return address(0);
    }

    /// @dev Read the current nonce and advance it. Returns the value that must appear in the
    ///      signed message, so a signature is spent exactly once.
    function _useNonce(address profile, bytes32 credentialId) internal returns (uint256 nonce) {
        nonce = credentialNonces[profile][credentialId];
        credentialNonces[profile][credentialId] = nonce + 1;
    }

    /// @dev Deactivate a credential on ONE profile and tombstone its ID and key THERE, permanently.
    ///      Other profiles are untouched.
    function _retireOnProfile(
        address profile,
        bytes32 credentialId,
        WebAuthnCredential storage target
    ) internal {
        target.active = false;
        retiredOnProfile[profile][credentialId] = true;
        retiredKeyOnProfile[profile][_keyHash(target.publicKeyX, target.publicKeyY)] = true;
        activeCredentialCount[profile] -= 1;
        emit CredentialRevoked(profile, credentialId);
    }

    /// @dev A credential may sign: active on this profile and NOT globally retired (by ID or key).
    ///      Global retirement must stop a compromised passkey everywhere at once, including on
    ///      profiles where it is still marked active, so every signing path checks it here.
    function _requireUsable(WebAuthnCredential storage cred, bytes32 credentialId) internal view {
        if (!cred.active) revert CredentialNotRegistered();
        if (
            retiredCredentialId[credentialId]
                || retiredPublicKey[_keyHash(cred.publicKeyX, cred.publicKeyY)]
        ) revert CredentialRetired();
    }

    /// @dev Refuses an ID or key retired GLOBALLY or on THIS profile, and an ID already bound to
    ///      another key.
    function _requireNotRetired(address profile, bytes32 credentialId, uint256 x, uint256 y)
        internal
        view
    {
        bytes32 keyHash = _keyHash(x, y);
        if (
            retiredCredentialId[credentialId] || retiredPublicKey[keyHash]
                || retiredOnProfile[profile][credentialId] || retiredKeyOnProfile[profile][keyHash]
        ) revert CredentialRetired();
        bytes32 bound = credentialIdKey[credentialId];
        if (bound != bytes32(0) && bound != keyHash) revert CredentialIdBoundToAnotherKey();
    }

    /// @notice Whether a credential ID can never be (re)enrolled on `profile`: retired on that
    ///         profile, or retired globally. (Off-chain clients read `retired(profile, id)`.)
    function retired(address profile, bytes32 credentialId) external view returns (bool) {
        return retiredOnProfile[profile][credentialId] || retiredCredentialId[credentialId];
    }

    /// @notice Whether a public key hash can never be (re)enrolled on `profile`: retired on that
    ///         profile, or retired globally.
    function retiredKey(address profile, bytes32 keyHash) external view returns (bool) {
        return retiredKeyOnProfile[profile][keyHash] || retiredPublicKey[keyHash];
    }

    /// @notice Whether a credential is retired on EVERY profile: its ID was retired globally, or
    ///         the key its ID is bound to was. Such a credential signs nowhere.
    function isRetiredGlobally(bytes32 credentialId) external view returns (bool) {
        if (retiredCredentialId[credentialId]) return true;
        bytes32 bound = credentialIdKey[credentialId];
        return bound != bytes32(0) && retiredPublicKey[bound];
    }

    function _keyHash(uint256 x, uint256 y) internal pure returns (bytes32) {
        return keccak256(abi.encode(x, y));
    }

    function _store(
        address profile,
        bytes32 credentialId,
        uint256 publicKeyX,
        uint256 publicKeyY,
        bytes32 credentialRpIdHash
    ) internal {
        bytes32 keyHash = _keyHash(publicKeyX, publicKeyY);
        if (credentialIdKey[credentialId] == bytes32(0)) credentialIdKey[credentialId] = keyHash;
        WebAuthnCredential storage cred = credentials[profile][credentialId];
        cred.publicKeyX = publicKeyX;
        cred.publicKeyY = publicKeyY;
        cred.rpIdHash = credentialRpIdHash;
        cred.active = true;
        profileCredentials[profile].push(credentialId);
        activeCredentialCount[profile] += 1;
    }
}
