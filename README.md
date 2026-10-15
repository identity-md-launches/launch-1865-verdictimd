# VerdictIMD (VERDICT)

VerdictIMD is an immutable ERC-20 with **1,000,000,000 tokens and 18 decimals**.
Its constructor mints the entire supply once to its immediate deployer. There are
no application contracts or post-deployment token settings.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `VerdictIMD` |
| Source | `src/VerdictIMD.sol` |
| Foundry artifact | `out/VerdictIMD.sol/VerdictIMD.json` |
| Name / symbol | `VerdictIMD` / `VERDICT` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Compiler | Solidity `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |
| External libraries to link | None |
| Intended launch chain | Ethereum, chain ID `1` |

The named constant `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` is the only
issuance amount. The constructor has no external calls and needs no existing
contracts. The token is deployed directly from its creation bytecode, without a
proxy or initializer. No owner, key, recipient or other configuration argument is
required.

For the IdentityMD launch, the factory is the immediate deployer and receives all
tokens. The wallet calling that factory receives nothing from the constructor.
For direct deployment by a wallet, that wallet receives all tokens. Any other
deployment wrapper must be able to forward the supply it receives.

## Behavior and assumptions

- Standard ERC-20 `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`
  and `totalSupply`, with OpenZeppelin custom errors on failure.
- Transfers deliver exactly the requested amount. There are no taxes, burns,
  rebases, transfer restrictions, recipient callbacks or external dependencies.
- Zero-value transfers between nonzero addresses are allowed and emit `Transfer`.
  Self-transfers preserve balances; delegated self-transfers still consume a
  finite allowance.
- Transfers to the zero address and approvals for the zero spender revert.
  Insufficient balances or allowances revert atomically.
- `approve` replaces the caller's previous allowance. Finite allowances decrease
  on `transferFrom`; `type(uint256).max` is an unlimited allowance and does not
  decrease. An explicit approval emits `Approval`; allowance consumption in the
  vendored implementation does not. Integrations should query `allowance`.
- There is no owner, minter, pause, blacklist, seizure, burn, upgrade or recovery
  function. The deployer retains no privilege after distributing its balance.
  `_mint` is internal and called only in the constructor; no later mint path is
  exposed.
- The contract has no payable entry point. Ordinary ETH transfers revert. Assets
  sent accidentally to the token contract, including VERDICT, cannot be recovered
  through it. Forced ETH does not affect token accounting.

## Launch and operational responsibilities

The launch service is responsible for deployment, distribution, liquidity setup,
and source verification. This repository supplies the token bytecode; it does
not broadcast transactions or write the separately generated `launch.json`.

The supplied launch policy allocates 10% to the factory's distributor, 80% to
liquidity, and the remaining 10% to the specified remainder recipient. Those
allocations occur **after** construction and are not encoded in this token.
The service also configures the IMD pair, pool fee and opening market cap from
the launch brief. No deployment-specific addresses are embedded in this code.

After launch, no token administrator or ongoing keeper is needed. Holders manage
their own balances and approvals. Spenders can transfer up to the approved
amount, so holders should approve only trusted spenders and revoke allowances
they no longer need. Changing an existing nonzero allowance has the standard
ERC-20 transaction-ordering race: a spender may spend the previous allowance
before the update is mined. Revoke to zero and confirm before approving a new
amount when that risk matters.

The deployer should verify the initial supply and recipient, complete the launch
distributions, and publish the deployed address and verified source. Independent
security review remains a release responsibility; these tests are not an audit.

## Build and test

From the repository root, with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xff046b8c36c21bcef0d08e0ebc22e2b1cd13f4181e769ca33b7751e224ef27b3 forge test
forge fmt --check
```

All Solidity dependencies are ordinary vendored files under `lib/`, so no package
installation or network access is needed once the pinned compiler is available.
`foundry.toml` enables neither FFI nor filesystem permissions. Tests use no forks,
RPC endpoints, environment reads, environment writes, secrets, clocks or files.
The shell seed above configures Foundry; test contracts do not access it.

The suite covers metadata, exact issuance and mint events, CREATE2 deployment
through a factory, full-balance and zero/self transfers, approval replacement and
revocation, finite/infinite allowances, invalid inputs, unauthorized spending,
failure rollback, absent administrative entry points, and runtime size/opcodes.
Fuzz tests run 1,024 cases each. Stateful invariants run 128 sequences of 64 calls
and compare balances and allowances to a separate ledger while checking supply
conservation.

The launch-flow test verifies exact token accounting for factory distribution,
claims, and transfers to and from a pool-manager fixture. It does not implement
Uniswap pricing or settlement. The supplied protected integration test needs the
network's separate factory/Uniswap harness and launch manifest, which are not
part of this repository; that full launch check is the verifier's responsibility.

## Dependencies

- OpenZeppelin Contracts **v5.0.2**, production ERC-20 and its required imports
  only, unmodified, under the included MIT license.
- Forge Standard Library **v1.9.7**, unmodified `src/`, used only for tests, with
  its included MIT and Apache-2.0 licenses.

`dependencies.json` records the upstream release, exact commit and SHA-256 of
each vendored file. No git submodules, compiler binaries or runtime downloads
are required.
