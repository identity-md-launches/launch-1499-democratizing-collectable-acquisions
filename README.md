# Democratizing Collectable Acquisions (DCA)

A fixed-supply ERC-20 for Ethereum. The implementation is
[`src/DCAToken.sol`](src/DCAToken.sol), using the vendored OpenZeppelin ERC-20.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity identifier | `DCAToken` |
| Name | `Democratizing Collectable Acquisions` |
| Symbol | `DCA` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` ETH |
| Initial recipient | The immediate deploying caller, `msg.sender` |
| Target chain | Ethereum, chain ID `1` |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. For factory deployment, the
factory receives the supply; for direct deployment, the deploying account does.
There is no constructor call to an external contract and no initialization step.
The compiled creation bytecode is available in `out/DCAToken.sol/DCAToken.json`.
It requires no library linking, constructor data, keys, or external addresses to
build or test.

## Behavior and assumptions

The brief specifies an ordinary ERC-20 with a fixed supply. Transfers deliver
exactly the requested amount. There are no transfer taxes, burns, rebases, trading
gates, maximum-wallet limits, or address exemptions. No account can mint after
construction, pause transfers, blacklist holders, seize balances, or upgrade this
deployment. The deployer has the same transfer and allowance rights as any holder.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
ERC-20 custom errors on invalid operations. Zero-value transfers between nonzero
addresses succeed and emit `Transfer`; transfers to the zero address revert,
including for zero amounts. Self-transfers preserve balances. Approval of the zero
address reverts. A holder may approve more than their current balance, but a
spender cannot transfer more than both the balance and allowance permit.

Approvals replace the previous allowance, and approving zero revokes it.
`transferFrom` reduces finite allowances; an allowance of `type(uint256).max`
remains unchanged when spent. Even a holder using `transferFrom` on their own
balance needs an allowance. `approve` emits `Approval`; this OpenZeppelin version
does not emit another `Approval` when `transferFrom` consumes an allowance.
Integrations should read `allowance()` for its current value.

There are no receiver callbacks or other external calls in token operations.
The contract has no payable entry point or asset recovery function. DCA or other
assets sent to the token contract itself can be stuck permanently. Ordinary ETH
transfers revert; forced ETH cannot be recovered.

## Build and test

From the repository root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are ordinary files under `lib/`, with their original
licenses and provenance recorded in [DEPENDENCIES.md](DEPENDENCIES.md). No
dependency download, submodule initialization, RPC, environment configuration,
FFI, or filesystem cheatcode permission is needed. The compiler is pinned by
version; Foundry's compiler cache must already contain 0.8.26 for offline checks.

Tests cover metadata, mint accounting and event, direct and CREATE2 factory
deployment, exact transfers, approvals and revocation, finite/infinite allowances,
zero and self transfers, unauthorized spending, invalid addresses, insufficient
balance/allowance, failure atomicity, unsupported privileged calls, and runtime
opcode restrictions. Fuzz tests exercise valid and invalid amounts (512 runs
each). Stateful invariants compare balances and allowances against a separate
ledger over randomized sequences (128 runs, 64 calls per run).

The local launch fixture checks a 10% distributor / 80% pool / 10% remainder
distribution, a subsequent claim, and exact transfers to and from a pool address.
It exercises only the token side; it is not an AMM or a Uniswap v4 settlement
test. The network's protected factory/PoolManager harness runs separately with
the launch's resolved parameters.

## Launch and operational responsibilities

The network deployer supplies the factory context and publishes the launch
manifest after acceptance. This repository does not create a manifest, deploy
contracts, broadcast transactions, or handle wallet keys. The factory distributes
the full constructor allocation. No application contract is part of this token.

The brief's launch economics remain external to the token: 10% for the swarm
distributor, 80% for the pool, and the remaining 10% for
`0x612a9bb008e16ef2d24f41dae9fc661831d93367`. The paired currency is the brief's
Ethereum IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, with a 1.25% pool
fee (`12500`), tick spacing `60`, and an initial market cap of
`2500000000000000000000` paired-currency minor units. The launch service derives
the actual opening price; these values are not constructor arguments or token
configuration. All addresses used by the tests are local fixtures only.

Before release, the network deployer is responsible for independent adversarial
review, the protected launch/AMM integration checks, confirming the artifact and
parameters, and source verification on the explorer. Local tests and the review
notes in [SECURITY.md](SECURITY.md) are not an independent security audit.

After launch there are no owner settings, keepers, or token maintenance calls.
Holders manage custody, destinations, and allowances. Prefer bounded approvals;
to replace a nonzero allowance safely, revoke it and confirm before granting the
new allowance, taking into account spending that may happen before revocation.
The launch operator is responsible for confirming distribution and recording the
deployed address. Lost funds and mistaken transfers have no administrative
recovery path.
