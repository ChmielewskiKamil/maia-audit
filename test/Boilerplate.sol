// SPDX-License-Identifier: MIT
// Modified version of https://github.com/zeroknots/boilerplate.sol/blob/main/test/Boilerplate.t.sol
// by @zeroknotsETH

pragma solidity ^0.8.15;

import {Test, console2 as console} from "forge-std/Test.sol";

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

import {PoolVariables} from "@talos/libraries/PoolVariables.sol";

import {IUniswapV3Pool, UniswapV3Staker, IUniswapV3Staker, IncentiveTime} from "@v3-staker/UniswapV3Staker.sol";

contract Boilerplate is Test {
    ////////////////////////////////////////////////////////////////////
    //                   Original UniV3StakerTest setup               //
    ////////////////////////////////////////////////////////////////////

    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint160;
    using FixedPointMathLib for uint128;
    using SafeCastLib for uint256;
    using SafeCastLib for int256;
    using SafeTransferLib for ERC20;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;

    bHermes bHermesToken;

    BaseV2Minter baseV2Minter;
    BaseV2GaugeManager baseV2GaugeManager;

    FlywheelGaugeRewards flywheelGaugeRewards;
    BribesFactory bribesFactory;

    FlywheelBoosterGaugeWeight flywheelGaugeWeightBooster;

    UniswapV3GaugeFactory uniswapV3GaugeFactory;
    UniswapV3Gauge gauge;
    UniswapV3Gauge gauge2;
    UniswapV3Gauge gauge3;
    UniswapV3Gauge gauge4;

    HERMES rewardToken;

    IUniswapV3Staker uniswapV3Staker;
    UniswapV3Staker uniswapV3StakerContract;

    IUniswapV3Staker.IncentiveKey key;
    bytes32 incentiveId;

    // Pool fee on arbitrum DAI/USDC pool is 0.01%
    uint24 constant poolFee = 100;

    ////////////////////////////////////////////////////////////////////
    //                      Testing Boilerplate                       //
    ////////////////////////////////////////////////////////////////////

    address public ATTACKER;
    address public DEPLOYER;
    address public ADMIN;
    address public ALICE;
    address public BOB;
    address public CHARLIE;
    address public EVE;

    bool activePrank;

    // Arbitrum forked by anvil, this way we can reduce calls to Alchemy
    // Make sure to first spin up anvil with --fork-url of arbitrum mainnet
    string internal localhost = vm.envString("LOCALHOST_RPC_URL");

    // Initialize is used instead of setUp() to have additional setUp() available
    // in each test contract that inherits from this one
    function initializeBoilerplate() public {
        makeAddr();
        vm.label(address(this), "Test contract");
        vm.createSelectFork(localhost);
        console.log("[BOILERPLATE] Current fork: %s", localhost);
    }

    ////////////////////////////////////////////////////////////////////
    //                      Addresses Arbitrum                        //
    ////////////////////////////////////////////////////////////////////

    // Old Arbitrum USDC
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    UniswapV3Factory uniswapV3Factory = UniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(payable(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

    // Token0: DAI, Token1: USDC
    UniswapV3Pool DAI_USDC_pool = UniswapV3Pool(0xF0428617433652c9dc6D1093A42AdFbF30D29f74);
    UniswapV3Pool mockPool2 = UniswapV3Pool(address(0x222));
    UniswapV3Pool mockPool3 = UniswapV3Pool(address(0x333));
    UniswapV3Pool mockPool4 = UniswapV3Pool(address(0x444));

    ////////////////////////////////////////////////////////////////////
    //                          Utilities                             //
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
        ALICE = address(0x1111);
        vm.label(ALICE, "ALICE");
        BOB = address(0x2222);
        vm.label(BOB, "BOB");
        CHARLIE = address(0x3333);
        vm.label(CHARLIE, "CHARLIE");
        EVE = address(0x4444);
        vm.label(EVE, "EVE");

        vm.label(address(nonfungiblePositionManager), "nonfungiblePositionManager");
        vm.label(address(DAI_USDC_pool), "DAI_USDC_pool");
        vm.label(address(uniswapV3Factory), "uniswapV3Factory");
    }
}
