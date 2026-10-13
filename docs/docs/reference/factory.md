# RealWorldAssetsV3Factory

Source: [`contracts/src/RealWorldAssetsV3Factory.sol`](https://github.com/family-labs/universal-goods-protocol/blob/main/contracts/src/RealWorldAssetsV3Factory.sol)

Deploys [`RealWorldAssetsV3`](./real-world-assets-v3) collections at deterministic CREATE2 addresses, one per product line, each owned by an organisation's Universal Profile. The compiled collection bytecode is embedded in the factory, so a predicted address can never drift from what is actually deployed.

The deployed factory's runtime bytecode on testnet and mainnet is byte-for-byte identical to `forge build` output from this repository.

## Functions

```solidity
function createRealWorldAssetsV3Deterministic(
    string memory name,
    string memory symbol,
    address owner,
    bytes32 salt
) external returns (address collection)

function computeAddress(bytes32 salt, string memory name, string memory symbol, address owner)
    public view returns (address)

function getInitCodeHash(string memory name, string memory symbol, address owner)
    public pure returns (bytes32)

function isDeployed(bytes32 salt, string memory name, string memory symbol, address owner)
    external view returns (bool)
```

**`createRealWorldAssetsV3Deterministic`** checks its inputs (non-zero owner, non-empty name, symbol exactly `RWA`), computes the address, and:

- if code already exists there, emits `RealWorldAssetsV3AlreadyDeployed` and returns that address. Because the init code includes the constructor arguments, existing code at that address is exactly the collection these arguments describe, owned by this owner;
- otherwise deploys with CREATE2, checks that the new collection's `owner()` equals `owner`, and emits `RealWorldAssetsV3Deployed`.

The call is idempotent, so a retried deployment after a timeout is safe.

**The address** is `keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]`, where `initCode = creationCode ++ abi.encode(name, symbol, owner)`. Changing any of the four inputs, including one character of the name, gives a different address.

Anyone can call the factory. A collection deployed by someone else for your profile would still be owned by your profile and could only be minted into by it.

## Events

| Event | When |
|---|---|
| `RealWorldAssetsV3Deployed(address indexed collection, address indexed owner, bytes32 indexed salt)` | A new collection was deployed |
| `RealWorldAssetsV3AlreadyDeployed(address indexed collection, address indexed owner, bytes32 indexed salt)` | The collection already existed and was returned |

`owner` is indexed so an indexer can answer "which collections does this organisation own". Public RPC endpoints often limit how many blocks one log query may span, so a reader that only wants one organisation's collections can also read `LSP12IssuedAssets[]` on its profile.

## Errors

`V3Factory_ZeroOwner()`, `V3Factory_EmptyName()`, `V3Factory_EmptySymbol()`, `V3Factory_DeploymentFailed()`, `V3Factory_OwnerMismatch(address expected, address actual)`, and `UG_SymbolMustBeExactlyRwa(string)` from the shared symbol rule.

## How the hosted platform calls it

The console's organisation profile calls the factory through `execute`, with the product title as `name`, `RWA` as the symbol, the profile as `owner`, and `salt = keccak256("ug:" + organisationId + ":" + productId)`, using the platform's own IDs. Other integrators can choose any salt scheme; the factory does not interpret it.

## Example: predict an address

```sh
cast call 0x11d51E1253f3962eDDf09A3D3dc6c29E533E0FDE \
  "computeAddress(bytes32,string,string,address)(address)" \
  0x0000000000000000000000000000000000000000000000000000000000000001 \
  "Example product" "RWA" 0x0000000000000000000000000000000000000001 \
  --rpc-url https://rpc.testnet.lukso.network
```

## Tests

`RealWorldAssetsV3Factory.t.sol`.
