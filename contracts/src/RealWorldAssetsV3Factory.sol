// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {RealWorldAssetsV3, requireRwaSymbol} from "./RealWorldAssetsV3.sol";

/**
 * @title RealWorldAssetsV3Factory
 * @notice Deploy `RealWorldAssetsV3` passport collections deterministically, one collection per
 *         product, each owned by the ORGANISATION'S UNIVERSAL PROFILE.
 *
 * WHY A FACTORY AT ALL, AND WHY THIS IS THE CHEAPER HALF OF A REAL CHOICE.
 * A product needs its own collection, because `RealWorldAssetsV3`'s constructor bakes the owner in
 * and `onlyOwner` compares against that and nothing else — so a collection cannot be shared between
 * organisations. The alternative considered and rejected was shipping the compiled CREATION
 * BYTECODE as a TypeScript constant and CREATE2-ing from the org's own profile. That works, but it
 * puts a copy of the compiler's output in a hand-maintained file: if the constant ever drifts from
 * `forge build`, the predicted address is one nothing deploys at — SILENTLY, and discovered only
 * after the address is saved and labels are printed. It needs a mandatory CI drift guard to
 * be safe at all.
 *
 * EMBEDDING `type(RealWorldAssetsV3).creationCode` HERE DELETES THAT ENTIRE FAILURE MODE. The
 * bytecode is placed by the same `forge build` that compiled the contract, lives on chain, and
 * cannot drift from a TypeScript file because there is no TypeScript file. What TypeScript needs is
 * one `view` call — `computeAddress` — the same shape the older V1 factory already offers.
 *
 * WHY *NOT* THE LSP16 SHAPE, WHICH IS THE OTHER LIVE PRECEDENT.
 * `RealWorldAssetLSP16Factory` deploys ERC-1167 PROXIES of a `RealWorldAssetInit` implementation.
 * That requires an `Init` variant, and `RealWorldAssetsV3` deliberately has none: its LSP4 token
 * type and LSP8 tokenId format are fixed IN THE CONSTRUCTOR and immutable afterwards
 * (`LSP4TokenTypeNotEditable`, `LSP8TokenIdFormatNotEditable`), and its docblock refuses an
 * `initDataKeys` / `initDataValues` loop by name — because a constructor runs where `onlyOwner`
 * does not exist, and LSP4's `_setData` override protects only three keys, NOT the tokenId format
 * and NOT `LSP17Extension:<selector>` keys. Writing a `RealWorldAssetsV3Init` to fit a proxy
 * factory would re-introduce precisely the initializer surface that contract was written to not
 * have.
 *
 * A minimal-proxy collection is also the wrong artefact for a brand: `extcodesize` 45, no
 * verifiable source at the collection address, and every read one `delegatecall` away.
 */
contract RealWorldAssetsV3Factory {
    /**
     * `owner` IS INDEXED BECAUSE IT IS THE THING WORTH FILTERING BY. An indexer answering "which
     * collections does this organisation own" reads this log, and that question is the whole of the
     * authority model.
     */
    event RealWorldAssetsV3Deployed(
        address indexed collection, address indexed owner, bytes32 indexed salt
    );

    /**
     * Emitted INSTEAD of `RealWorldAssetsV3Deployed` when the collection was already there. A
     * caller may treat the two outcomes as one (see the idempotence argument below), but a log
     * claiming a deployment that did not happen would make block explorers and indexers
     * disagree about when a collection came into existence.
     */
    event RealWorldAssetsV3AlreadyDeployed(
        address indexed collection, address indexed owner, bytes32 indexed salt
    );

    error V3Factory_ZeroOwner();
    error V3Factory_EmptyName();
    error V3Factory_EmptySymbol();
    error V3Factory_DeploymentFailed();
    error V3Factory_OwnerMismatch(address expected, address actual);

    /**
     * @notice Deploy the collection for `(name, symbol, owner, salt)`, or return the one already
     *         there.
     *
     * IT IS IDEMPOTENT, AND THAT IS A SAFETY PROPERTY RATHER THAN A CONVENIENCE.
     *
     * A CREATE2 address is `keccak256(0xff, factory, salt, keccak256(initCode))[12:]`, and the init
     * code here contains BOTH the compiled `RealWorldAssetsV3` and the ABI-encoded constructor
     * arguments. So if code already exists at the computed address it is not merely "some
     * contract" — it is byte-for-byte the contract these exact arguments would have produced, owned
     * by this exact `owner`. Returning it is therefore indistinguishable from having deployed it,
     * and there is no case where a caller receives something other than what it asked for.
     * (`RealWorldAssetsV3` has no `SELFDESTRUCT`, and post-Cancun that opcode cannot clear code
     * deployed in an earlier transaction anyway, so the slot cannot be recycled under us.)
     *
     * THE ALTERNATIVE — REVERTING, AS BOTH EXISTING FACTORIES DO — TURNS A HARMLESS RACE INTO A
     * FAILED PRODUCT DEPLOY. Anyone watching the mempool can copy a pending deploy and send it
     * first. They cannot steal anything by doing so: the arguments are inside the init code, so the
     * only collection they can place at this address is the intended one, owned by the intended
     * organisation, at their own expense. Front-running this is a DONATION. But under a reverting factory that donation
     * makes the operator's own transaction fail, on their gas, with "deployment failed" — and
     * leaves the product with no saved address for a collection that visibly exists on chain.
     *
     * @param owner THE ORGANISATION'S UNIVERSAL PROFILE. It is a PARAMETER, never `msg.sender`
     *              and never `address(this)`. A factory that made ITSELF the owner would produce
     *              collections nobody could ever mint from; one that used `msg.sender` would hand
     *              ownership to whichever relayer or EOA happened to pay for the transaction. Both
     *              fail silently — the collection deploys, looks correct in an explorer, and
     *              reverts every mint with `OwnableCallerNotTheOwner`.
     * @param salt  Namespaces one organisation's products from another's. It is NOT the security
     *              boundary: `owner` already is, because it sits inside the init code and therefore
     *              inside the address.
     */
    function createRealWorldAssetsV3Deterministic(
        string memory name,
        string memory symbol,
        address owner,
        bytes32 salt
    ) external returns (address collection) {
        /**
         * REFUSE BEFORE SPENDING THE GAS, AND ESPECIALLY BEFORE MAKING SOMETHING IMMUTABLE.
         * `ERC725Y`'s constructor rejects the zero owner, but only after the deployment is paid
         * for. An empty name or symbol is worse: it SUCCEEDS, and is then permanent —
         * `LSP4DigitalAssetMetadata._setData` reverts `LSP4TokenNameNotEditable`. A nameless
         * passport collection cannot be fixed, only abandoned.
         */
        if (owner == address(0)) revert V3Factory_ZeroOwner();
        if (bytes(name).length == 0) revert V3Factory_EmptyName();
        if (bytes(symbol).length == 0) revert V3Factory_EmptySymbol();
        /**
         * THE `RWA` SYMBOL RULE, CHECKED HERE *AS WELL AS* IN THE CONSTRUCTOR — AND THIS IS
         * NOT BELT-AND-BRACES, IT IS THE ONLY WAY THE FAILURE IS LEGIBLE.
         *
         * `create2` in assembly returns `address(0)` when the constructor reverts and DISCARDS
         * the revert data. Left to the constructor alone, a caller who forgot the prefix would
         * see `V3Factory_DeploymentFailed()` — an error naming nothing, on a payload that is
         * perfectly well formed. Reverting with the SAME error the constructor would have used
         * means one rule, one name, and a message that says what to fix, whichever entry point
         * you arrived through. The rule itself has ONE implementation: `requireRwaSymbol` is a
         * file-level function in `RealWorldAssetsV3.sol`, imported here, never copied.
         */
        requireRwaSymbol(symbol);

        bytes memory initCode = _initCode(name, symbol, owner);
        address predicted = _addressOf(salt, keccak256(initCode));

        if (predicted.code.length != 0) {
            emit RealWorldAssetsV3AlreadyDeployed(predicted, owner, salt);
            return predicted;
        }

        assembly {
            collection := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (collection == address(0)) revert V3Factory_DeploymentFailed();

        /**
         * VERIFY THE AUTHORITY WE JUST CREATED, IN THE TRANSACTION THAT CREATED IT.
         *
         * This mirrors `DeployRealWorldAssetsV3.s.sol`, which asserts `collection.owner() ==
         * RWA_OWNER` after broadcast, and the reason is the same and worth repeating: a collection
         * that ended up owned by the DEPLOYER instead of the organisation looks IDENTICAL from
         * outside — same bytecode, same address derivation, same event — and is discovered only
         * when every mint reverts. Reverting here means a wrong-owner collection can never become
         * a saved product address.
         *
         * It is cheap, and it is not redundant with passing the argument. It is the argument
         * being CHECKED rather than trusted, which is the difference between this file being
         * correct and this file being believed to be correct.
         */
        /**
         * `payable(...)` IS REQUIRED BY THE COMPILER, NOT BY INTENT, and it is worth a line so
         * nobody reads value-handling into it. `RealWorldAssetsV3` inherits LSP8's
         * `LSP17Extendable` fallback, which is `payable`, so Solidity refuses a direct
         * non-payable `address` → contract conversion. No ether is sent here: the `create2` above
         * passes value 0 and `owner()` is a `view` call.
         */
        address actualOwner = RealWorldAssetsV3(payable(collection)).owner();
        if (actualOwner != owner) revert V3Factory_OwnerMismatch(owner, actualOwner);

        emit RealWorldAssetsV3Deployed(collection, owner, salt);
    }

    /**
     * @notice The address `createRealWorldAssetsV3Deterministic` will use for these arguments.
     *
     * CALLABLE BEFORE ANY BYTECODE EXISTS — which is what lets an app save the product's
     * collection address and print labels in the same step that requests the deploy. This is the
     * property the V1 flow already depends on through the LSP16 factory's `computeAddress`.
     */
    function computeAddress(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner
    ) public view returns (address) {
        return _addressOf(salt, getInitCodeHash(name, symbol, owner));
    }

    /// @notice `keccak256(init code)` for these constructor arguments.
    function getInitCodeHash(
        string memory name,
        string memory symbol,
        address owner
    ) public pure returns (bytes32) {
        return keccak256(_initCode(name, symbol, owner));
    }

    /**
     * @notice Whether the collection for these arguments has already been deployed.
     * @dev Saves the caller a second RPC round trip: a client would otherwise compute the address
     *      here and then ask the node for `eth_getCode` separately.
     */
    function isDeployed(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address owner
    ) external view returns (bool) {
        return computeAddress(salt, name, symbol, owner).code.length != 0;
    }

    function _initCode(
        string memory name,
        string memory symbol,
        address owner
    ) internal pure returns (bytes memory) {
        /**
         * THE CONSTRUCTOR ARGUMENTS ARE PART OF THE ADDRESS, and that is the whole security
         * argument for the idempotence above. Change the name, the symbol or the owner and the
         * init code hash changes and so does the address — so an address can only ever hold the
         * collection its own arguments describe.
         */
        return abi.encodePacked(
            type(RealWorldAssetsV3).creationCode,
            abi.encode(name, symbol, owner)
        );
    }

    function _addressOf(bytes32 salt, bytes32 initCodeHash) internal view returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))
            )
        );
    }
}
