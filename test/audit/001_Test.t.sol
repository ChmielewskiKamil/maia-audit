// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./boilerplate/Boilerplate.sol";
import "./boilerplate/DeployedContracts.sol";

contract Test1 is Boilerplate {
    function test_1() external {
        vm.createSelectFork(localhost);

        assertEq(hermes.owner(), DEPLOYER);
    }
}
