// SPDX-License-Identifier: MIT
// Modified version of https://github.com/zeroknots/boilerplate.sol/blob/main/test/Boilerplate.t.sol
// by @zeroknotsETH

pragma solidity ^0.8.15;

import {Test, stdStorage, StdStorage, console2 as console} from "forge-std/Test.sol";

contract Boilerplate is Test {
    using stdStorage for StdStorage;

    address public ATTACKER;
    address public USER1;
    address public USER2;
    address public USER3;
    address public USER4;
    address public DEPLOYER;

    bool public activePrank;

    // Forking
    string internal mainnet = vm.envString("MAINNET_RPC_URL");
    // Mainnet forked by anvil, this way we can reduce calls to Alchemy
    string internal localhost = vm.envString("LOCALHOST_RPC_URL");

    function initializeBoilerplate() public {
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
        ATTACKER = address(0x1337);
        vm.label(ATTACKER, "ATTACKER");
        USER1 = address(0x1111);
        vm.label(USER1, "USER1");
        USER2 = address(0x2222);
        vm.label(USER2, "USER2");
        USER3 = address(0x3333);
        vm.label(USER3, "USER3");
        USER4 = address(0x4444);
        vm.label(USER4, "USER4");
    }

    function readSlot(address target, bytes4 selector) public returns (bytes32) {
        uint256 slot = stdstore.target(target).sig(selector).find();
        return vm.load(target, bytes32(slot));
    }
}
