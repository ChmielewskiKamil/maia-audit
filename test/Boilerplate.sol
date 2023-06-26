// SPDX-License-Identifier: MIT
// Modified version of https://github.com/zeroknots/boilerplate.sol/blob/main/test/Boilerplate.t.sol
// by @zeroknotsETH

pragma solidity ^0.8.15;

import {Test, stdStorage, StdStorage, console2 as console} from "forge-std/Test.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Imports for minting UNI-V3 positions
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

import {UniswapV3Factory, UniswapV3Pool} from "@uniswap/v3-core/contracts/UniswapV3Factory.sol";

import {IWETH9} from "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";
import {NonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/NonfungiblePositionManager.sol";

import {
    UniswapV3GaugeFactory,
    FlywheelGaugeRewards,
    BaseV2GaugeManager
} from "@gauges/factories/UniswapV3GaugeFactory.sol";
import {BribesFactory, FlywheelBoosterGaugeWeight} from "@gauges/factories/BribesFactory.sol";
import {UniswapV3Gauge, BaseV2Gauge} from "@gauges/UniswapV3Gauge.sol";

import {BaseV2Minter} from "@hermes/minters/BaseV2Minter.sol";
import {bHermes} from "@hermes/bHermes.sol";
import {HERMES} from "@hermes/tokens/HERMES.sol";

import {UniswapV3Assistant} from "@test/test-utils/UniswapV3Assistant.t.sol";

import {PoolVariables} from "@talos/libraries/PoolVariables.sol";

import {IUniswapV3Pool, UniswapV3Staker, IUniswapV3Staker, IncentiveTime} from "@v3-staker/UniswapV3Staker.sol";

contract Boilerplate is Test {
    using stdStorage for StdStorage;

    address public ATTACKER;
    address public USER1;
    address public USER2;
    address public USER3;
    address public USER4;
    address public DEPLOYER;
    address public ADMIN;

    bool public activePrank;

    // Forking
    string internal mainnet = vm.envString("MAINNET_RPC_URL");
    // Mainnet forked by anvil, this way we can reduce calls to Alchemy
    string internal localhost = vm.envString("LOCALHOST_RPC_URL");

    function initializeBoilerplate() public {
        makeAddr();
        vm.label(address(this), "Test contract");
        vm.createSelectFork(localhost);
    }

    ////////////////////////////////////////////////////////////////////
    //                      Addresses Arbitrum                        //
    ////////////////////////////////////////////////////////////////////

    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    UniswapV3Factory uniswapV3Factory = UniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(payable(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

    // UniV3 ETH/USDC 0.05% pool
    // https://info.uniswap.org/#/arbitrum/pools/0xc31e54c7a869b9fcbecc14363cf510d1c41fa443
    UniswapV3Pool ETH_USDC_pool = UniswapV3Pool(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    // Token0: DAI, Token1: USDC
    UniswapV3Pool DAI_USDC_pool = UniswapV3Pool(0xF0428617433652c9dc6D1093A42AdFbF30D29f74);

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
        DEPLOYER = address(0xDEADBEEF);
        vm.label(DEPLOYER, "DEPLOYER");
        ADMIN = address(0xCAFE);
        vm.label(ADMIN, "ADMIN");
        USER1 = address(0x1111);
        vm.label(USER1, "USER1");
        USER2 = address(0x2222);
        vm.label(USER2, "USER2");
        USER3 = address(0x3333);
        vm.label(USER3, "USER3");
        USER4 = address(0x4444);
        vm.label(USER4, "USER4");
        vm.label(address(nonfungiblePositionManager), "nonfungiblePositionManager");
        vm.label(address(DAI_USDC_pool), "DAI_USDC_pool");
    }

    function readSlot(address target, bytes4 selector) public returns (bytes32) {
        uint256 slot = stdstore.target(target).sig(selector).find();
        return vm.load(target, bytes32(slot));
    }
}
