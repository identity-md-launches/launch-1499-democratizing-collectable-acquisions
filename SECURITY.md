# Security review notes

Scope: `DCAToken` and its vendored ERC-20 implementation, compiled with the root
Foundry settings. The supplied eth-security reference was used as a checklist.
This is a local source review and test record, not an independent audit.

## Reviewed properties

- Supply is minted at one constructor call site, in exactly 18-decimal units.
  Runtime entry points do not reach mint or burn. The constant `INITIAL_SUPPLY`
  is `10^27`; public operations preserve `totalSupply()` at that value.
- Metadata and transfer behavior have no setters. There is no owner, minter,
  pauser, upgrade authority, proxy, initializer, or privileged transfer path.
- Transfers debit the caller; delegated transfers require the source holder's
  allowance. A revert restores both allowance and balances. Zero addresses are
  rejected where ERC-20 requires a valid participant; zero-value transfers remain
  supported for compatibility.
- The OpenZeppelin implementation checks sufficient balance and allowance before
  subtraction. Its unchecked additions/subtractions are bounded by conservation
  of the fixed supply and the corresponding balance/allowance checks.
- Token operations and construction make no external calls, so recipient
  reentrancy is not an interaction path. No oracle, randomness, signature,
  timestamp, or reserve-price assumptions exist in this contract.
- The factory receives the whole supply on CREATE2 deployment. No address-specific
  rules alter claims, pool transfers, or ordinary holder transfers. The factory
  distribution and actual Uniswap v4 lifecycle remain the launch service's work.
- Compiled runtime is checked for forbidden `DELEGATECALL`, `CALLCODE`, and
  `SELFDESTRUCT`, accounting for PUSH data, and against the EIP-170 size limit.

## Validation and limits

The delivered tests exercise success paths, failure paths, supply conservation,
allowance accounting, and failed admin/mint probes. Stateful tests compare a
separate ledger to balances and allowances after interleaved operations. Each
test deploys fresh state and requires no RPC or environment variables.

Executed with Foundry 1.8.5 and Solidity 0.8.26:

- `forge build`: passed; runtime size 1,752 bytes and no library link references.
- `forge test`: passed, 33 reported tests with no failures or skips (32 unit,
  fuzz, and launch tests plus one grouped invariant suite with three properties).
  Each of the three fuzz tests ran 512 cases; the stateful suite ran 8,192 calls
  with no reverts.
- `forge fmt --check`: passed.
- A clean copy containing only delivered source, tests, dependencies, and build
  configuration passed `forge build --offline`, `forge test --offline --threads 4`,
  and `forge fmt --check`, with an empty process environment and no input files or
  preexisting artifacts. Its creation and runtime bytecode matched the original
  build exactly. The machine's preinstalled compiler cache provided solc 0.8.26.

Slither, Mythril, and the platform's external protected launch harness were not
run. The local pool fixture checks token transfers, not AMM execution. Independent
adversarial review and the platform integration checks remain release
responsibilities.

## Holder and integration considerations

Approvals authorize a spender to transfer holdings. Unlimited approvals remain
unlimited until revoked, and changing an allowance has the standard ERC-20
transaction-ordering considerations. There is no permit extension.

Users must confirm recipients and avoid sending assets to this contract. It has
no rescue function, pause mechanism, or upgrade path. The lack of an administrator
also means that mistakes and a future vulnerability cannot be fixed in place.
