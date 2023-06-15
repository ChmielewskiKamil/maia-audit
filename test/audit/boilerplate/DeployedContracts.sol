// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3GaugeFactory} from "@gauges/interfaces/IUniswapV3GaugeFactory.sol";
import {bHermesBoost} from "@hermes/tokens/bHermesBoost.sol";

import {HERMES} from "@hermes/tokens/HERMES.sol";

/// @title Addresses
/// @author @kamilchmielu
/// @notice This contract holds every address that is needed for the tests
abstract contract DeployedContracts {
    ////////////////////////////////////////////////////////////////////
    //                           Arbitrum                             //
    ////////////////////////////////////////////////////////////////////
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager public nonfungiblePositionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    ////////////////////////////////////////////////////////////////////
    //                            Anvil                               //
    ////////////////////////////////////////////////////////////////////
    // bHermesBoost public hermesGaugeBoost;
    // IUniswapV3GaugeFactory public uniswapV3GaugeFactory = IUniswapV3GaugeFactory ();
    HERMES public hermes = HERMES(0x8ce361602B935680E8DeC218b820ff5056BeB7af);
}
