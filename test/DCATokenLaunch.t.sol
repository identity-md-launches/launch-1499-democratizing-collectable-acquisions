// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DCAToken} from "../src/DCAToken.sol";

/// @dev A local fixture for deployment and exact transfers, not a production factory or AMM.
contract TokenFactoryFixture {
    DCAToken public token;

    function deploy(bytes32 salt) external returns (DCAToken) {
        token = new DCAToken{salt: salt}();
        return token;
    }

    function distribute(address distributor, address pool, address remainder) external {
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply / 10));
        require(token.transfer(pool, supply * 8 / 10));
        require(token.transfer(remainder, supply / 10));
    }
}

contract DCATokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    TokenFactoryFixture internal factory;
    DCAToken internal token;
    address internal distributor = makeAddr("distributor");
    address internal pool = makeAddr("pool");
    address internal remainder = makeAddr("remainder");
    address internal holder = makeAddr("holder");
    address internal other = makeAddr("other");

    function setUp() public {
        factory = new TokenFactoryFixture();
        token = factory.deploy(keccak256("DCA launch test"));
    }

    function test_create2MintsEntireSupplyToFactoryNotOrigin() public view {
        bytes32 salt = keccak256("DCA launch test");
        bytes32 predictedHash =
            keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(DCAToken).creationCode)));
        // The lower 160 bits are the CREATE2 address by definition.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(address(token), address(uint160(uint256(predictedHash))));
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(tx.origin), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_distributionClaimsAndPoolTransfersAreExact() public {
        factory.distribute(distributor, pool, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.balanceOf(remainder), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(holder, SUPPLY / 10));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(holder), SUPPLY / 10);

        // Exercise the token leg in both directions. AMM pricing/settlement is external.
        vm.prank(pool);
        assertTrue(token.transfer(other, 50 ether));
        assertEq(token.balanceOf(other), 50 ether);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10 - 50 ether);
        vm.prank(other);
        assertTrue(token.transfer(pool, 50 ether));
        assertEq(token.balanceOf(other), 0);
        assertEq(token.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrPrivilegedEntryPoints() public {
        factory.distribute(distributor, pool, remainder);
        vm.prank(distributor);
        token.transfer(holder, SUPPLY / 10);

        bytes[] memory attempts = new bytes[](24);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", other, SUPPLY);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        attempts[4] = abi.encodeWithSignature("setOwner(address)", other);
        attempts[5] = abi.encodeWithSignature("transferOwnership(address)", other);
        attempts[6] = abi.encodeWithSignature("upgradeTo(address)", other);
        attempts[7] = abi.encodeWithSignature("initialize(address)", other);
        attempts[8] = abi.encodeWithSignature("unpause()");
        attempts[9] = abi.encodeWithSignature("setMinter(address)", other);
        attempts[10] = abi.encodeWithSignature("pause()");
        attempts[11] = abi.encodeWithSignature("blacklist(address)", holder);
        attempts[12] = abi.encodeWithSignature("blocklist(address)", holder);
        attempts[13] = abi.encodeWithSignature("freeze(address)", holder);
        attempts[14] = abi.encodeWithSignature("freezeAccount(address)", holder);
        attempts[15] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        attempts[16] = abi.encodeWithSignature("setBlocked(address,bool)", holder, true);
        attempts[17] = abi.encodeWithSignature("lock(address)", holder);
        attempts[18] = abi.encodeWithSignature("disableTransfers()");
        attempts[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[20] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1);
        attempts[21] = abi.encodeWithSignature("seize(address)", holder);
        attempts[22] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[23] = abi.encodeWithSignature("_mint(address,uint256)", other, SUPPLY);

        address[3] memory callers = [address(factory), holder, other];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < attempts.length; ++j) {
                vm.prank(callers[i]);
                (bool ok,) = address(token).call(attempts[j]);
                assertFalse(ok, "unsupported privileged call succeeded");
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(holder), SUPPLY / 10);
                assertEq(token.balanceOf(other), 0);
            }
        }
        vm.prank(holder);
        assertTrue(token.transfer(other, SUPPLY / 10));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(other), SUPPLY / 10);
    }

    function test_runtimeContainsNoDangerousOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
