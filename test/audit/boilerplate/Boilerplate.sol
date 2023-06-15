// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {Test, stdStorage, StdStorage, console2 as console} from "forge-std/Test.sol";

import {DeployedContracts} from "./DeployedContracts.sol";

contract Boilerplate is Test, DeployedContracts {
    using stdStorage for StdStorage;

    /// @dev DEPLOYER is the address of 9th unlocked anvil account
    /// The deployment script will use this address as sender to deploy all of the contracts
    address public immutable DEPLOYER = address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720);
    address public immutable ADMIN = address(0xDEADBEEF);
    address public immutable ATTACKER = address(0x1337);
    address public immutable USER1 = address(0x1111);
    address public immutable USER2 = address(0x2222);
    address public immutable USER3 = address(0x3333);
    address public immutable USER4 = address(0x4444);

    bool public activePrank;

    // Forking
    string internal mainnet = vm.envString("MAINNET_RPC_URL");
    // Mainnet forked by anvil, this way we can reduce calls to Alchemy
    string internal localhost = vm.envString("LOCALHOST_RPC_URL");

    function setUp() public {
        makeAddr();
    }

    ////////////////////////////////////////////////////////////////////
    //                           Utilities                            //
    ////////////////////////////////////////////////////////////////////

    function suStart(address user) public {
        vm.startPrank(user);
        activePrank = true;
    }

    function suStop() public {
        vm.stopPrank();
        activePrank = false;
    }

    modifier asUser(address user) {
        suStart(user);
        _;
        suStop();
    }

    function makeAddr() public {
        vm.label(ATTACKER, "ATTACKER");
        vm.label(DEPLOYER, "DEPLOYER");
        vm.label(ADMIN, "ADMIN");
        vm.label(USER1, "USER1");
        vm.label(USER2, "USER2");
        vm.label(USER3, "USER3");
        vm.label(USER4, "USER4");
    }

    function readSlot(address target, bytes4 selector) public returns (bytes32) {
        uint256 slot = stdstore.target(target).sig(selector).find();
        return vm.load(target, bytes32(slot));
    }
}
