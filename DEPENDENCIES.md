# Vendored dependencies

Dependencies are included as ordinary source files, not submodules. No package
manager or network access is required to resolve imports. Vendored files retain
their upstream contents and licenses; project formatting does not rewrite them.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.0.2) | `v5.0.2` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol` and license | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/releases/tag/v1.9.7) | `v1.9.7` | `src/` and licenses (tests only) | MIT or Apache-2.0 |

Source archive URLs and SHA-256 digests used when vendoring:

```text
https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a

https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
```

The production contract imports only OpenZeppelin's minimal ERC-20 dependency
closure. Its internal helpers compile into the token, leaving no deployed library
addresses to configure. `forge-std` is used only by local tests; none of its
cheatcodes are part of production bytecode.
