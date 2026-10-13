// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Democratizing Collectable Acquisions (DCA)
/// @notice A fixed-supply ERC-20 with 18 decimals and ordinary, untaxed transfers.
/// @dev The immediate deploying caller receives the entire supply. There are no
/// external mint, burn, administration, or upgrade functions.
contract DCAToken is ERC20 {
    /// @notice One billion DCA, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Democratizing Collectable Acquisions", "DCA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
