// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Boilerplate} from "../Boilerplate.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

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

import {UniswapV3Assistant} from "@test/test-utils/UniswapV3Assistant.t.sol";

import {PoolVariables} from "@talos/libraries/PoolVariables.sol";

import {IUniswapV3Pool, UniswapV3Staker, IUniswapV3Staker, IncentiveTime} from "@v3-staker/UniswapV3Staker.sol";

contract Audit_UniswapV3Staker is Boilerplate, IERC721Receiver {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint160;
    using FixedPointMathLib for uint128;
    using SafeCastLib for uint256;
    using SafeCastLib for int256;
    using SafeTransferLib for ERC20;
    using SafeTransferLib for MockERC20;

    //////////////////////////////////////////////////////////////////
    //                          VARIABLES
    //////////////////////////////////////////////////////////////////
    bHermes bHermesToken;

    BaseV2Minter baseV2Minter;

    FlywheelGaugeRewards flywheelGaugeRewards;
    BribesFactory bribesFactory;

    FlywheelBoosterGaugeWeight flywheelGaugeWeightBooster;

    UniswapV3GaugeFactory uniswapV3GaugeFactory;
    UniswapV3Gauge gauge;

    MockERC20 token0;
    MockERC20 token1;

    MockERC20 rewardToken;

    UniswapV3Factory uniswapV3Factory;
    NonfungiblePositionManager nonfungiblePositionManager;

    IUniswapV3Pool pool;
    UniswapV3Pool poolContract;

    IWETH9 WETH9 = IWETH9(address(0));

    IUniswapV3Staker uniswapV3Staker;
    UniswapV3Staker uniswapV3StakerContract;

    IUniswapV3Staker.IncentiveKey key;
    bytes32 incentiveId;

    uint24 constant poolFee = 3000;

    //////////////////////////////////////////////////////////////////
    //                          SET UP
    //////////////////////////////////////////////////////////////////

    function setUp() public {
        initializeBoilerplate();
        vm.warp(52 weeks);
        token1 = new MockERC20("test token", "TKN", 18);
        token0 = new MockERC20("test token", "TKN", 18);
        rewardToken = new MockERC20("test reward token", "RTKN", 18);

        (uniswapV3Factory, nonfungiblePositionManager) = UniswapV3Assistant.deployUniswapV3();

        bHermesToken = new bHermes(rewardToken, address(this), 1 weeks, 12 hours);

        flywheelGaugeWeightBooster = new FlywheelBoosterGaugeWeight(bHermesToken.gaugeWeight());

        bribesFactory = new BribesFactory(
            BaseV2GaugeManager(address(this)),
            flywheelGaugeWeightBooster,
            1 weeks,
            address(this)
        );

        baseV2Minter = new BaseV2Minter(
            address(bHermesToken),
            address(flywheelGaugeRewards),
            address(this)
        );

        flywheelGaugeRewards = new FlywheelGaugeRewards(
            address(rewardToken),
            address(this),
            bHermesToken.gaugeWeight(),
            baseV2Minter
        );
        baseV2Minter.initialize(flywheelGaugeRewards);

        uniswapV3GaugeFactory = new UniswapV3GaugeFactory(
            BaseV2GaugeManager(address(0)),
            bHermesToken.gaugeBoost(),
            uniswapV3Factory,
            nonfungiblePositionManager,
            flywheelGaugeRewards,
            bribesFactory,
            address(this)
        );

        vm.mockCall(address(0), abi.encodeWithSignature("addGauge(address)"), abi.encode(""));

        uniswapV3StakerContract = uniswapV3GaugeFactory.uniswapV3Staker();

        uniswapV3Staker = IUniswapV3Staker(address(uniswapV3StakerContract));
    }

    // Create a new Uniswap V3 Gauge from a Uniswap V3 pool
    function createGaugeAndAddToGaugeBoost(IUniswapV3Pool _pool, uint256 minWidth)
        internal
        returns (UniswapV3Gauge _gauge)
    {
        uniswapV3GaugeFactory.createGauge(address(_pool), abi.encode(uint24(minWidth)));
        _gauge = UniswapV3Gauge(address(uniswapV3GaugeFactory.strategyGauges(address(_pool))));
        bHermesToken.gaugeBoost().addGauge(address(_gauge));
    }

    // Create a Uniswap V3 Staker incentive
    function createIncentive(IUniswapV3Staker.IncentiveKey memory _key, uint256 amount) internal {
        uniswapV3Staker.createIncentive(_key, amount);
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function newNFT(int24 tickLower, int24 tickUpper, uint128 sqrtPriceX96) internal returns (uint256 tokenId) {
        (uint256 amount0, uint256 amount1) = PoolVariables.amountsForLiquidity(pool, sqrtPriceX96, tickLower, tickUpper);

        token0.mint(address(this), amount0);
        token1.mint(address(this), amount1);
        token0.approve(address(nonfungiblePositionManager), amount0);
        token1.approve(address(nonfungiblePositionManager), amount1);

        pool.slot0();

        tokenId = UniswapV3Assistant.mintPosition(
            nonfungiblePositionManager,
            address(token0),
            address(token1),
            poolFee,
            tickLower,
            tickUpper,
            amount0,
            amount1
        );
        vm.warp(block.timestamp + 100);
    }

    function testRestake() public {
    }
}
