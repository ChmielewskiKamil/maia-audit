// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

import {Script, console2 as console} from "forge-std/Script.sol";

import {HERMES} from "@hermes/tokens/HERMES.sol";
import {bHermes as bHERMES} from "@hermes/bHermes.sol";
import {BaseV2GaugeManager} from "@gauges/factories/BaseV2GaugeManager.sol";
import {UniswapV3GaugeFactory} from "@gauges/factories/UniswapV3GaugeFactory.sol";

contract HermesDeployment is Script {
    HERMES public hermes;
    bHERMES public bHermes;
    BaseV2GaugeManager public baseV2GaugeManager;
    UniswapV3GaugeFactory public uniswapV3GaugeFactory;

    address public constant DEPLOYER = address(0xa0Ee7A142d267C1f36714E4a8F75612F20a79720);
    uint256 anvilDeployerPrivateKey = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    address public constant ADMIN = address(0xDEADBEEF);

    function run() public {
        vm.startBroadcast(anvilDeployerPrivateKey);

        hermes = new HERMES({_owner: DEPLOYER });
        // Values taken from bHermesTest.t.sol
        bHermes = new bHERMES({_hermes: hermes, _owner: DEPLOYER, _gaugeCycleLength: 1000, _incrementFreezeWindow: 100});

        baseV2GaugeManager = new BaseV2GaugeManager({_bHermes: bHermes, _owner: DEPLOYER, _admin: ADMIN});
        /*
        BaseV2GaugeManager _gaugeManager,
        bHermesBoost _bHermesBoost,
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        FlywheelGaugeRewards _flywheelGaugeRewards,
        BribesFactory _bribesFactory,
        address _owner
        */
        uniswapV3GaugeFactory = new UniswapV3GaugeFactory({_baseV2GaugeManager: baseV2GaugeManager, _bHermesBoost: bHermes.gaugeBoost()});

        vm.stopBroadcast();
        console.log("HERMES deployed at: ", address(hermes));
    }
}

