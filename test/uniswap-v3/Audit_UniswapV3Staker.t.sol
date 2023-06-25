// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../Boilerplate.sol";

contract Audit_UniswapV3Staker is Boilerplate, IERC721Receiver {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint160;
    using FixedPointMathLib for uint128;
    using SafeCastLib for uint256;
    using SafeCastLib for int256;
    using SafeTransferLib for ERC20;
    using SafeTransferLib for MockERC20;

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

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

    // TODO Substitute this with HERMES?
    MockERC20 rewardToken;

    IUniswapV3Staker uniswapV3Staker;
    UniswapV3Staker uniswapV3StakerContract;

    IUniswapV3Staker.IncentiveKey key;
    IUniswapV3Staker.IncentiveKey keyTest;
    bytes32 incentiveId;

    // Pool fee on arbitrum is 0.05%
    uint24 constant poolFee = 100;

    //////////////////////////////////////////////////////////////////
    //                          SET UP
    //////////////////////////////////////////////////////////////////

    function setUp() public {
        initializeBoilerplate();
        vm.warp(52 weeks);

        vm.startPrank(DEPLOYER);
        rewardToken = new MockERC20("test reward token", "RTKN", 18);

        bHermesToken =
        new bHermes({ _hermes: rewardToken, _owner: address(this), _gaugeCycleLength: 1 weeks, _incrementFreezeWindow: 12 hours });

        flywheelGaugeWeightBooster = new FlywheelBoosterGaugeWeight({ _bHermesGauges: bHermesToken.gaugeWeight() });

        bribesFactory = new BribesFactory(
            // This contract acts as a manager?
            BaseV2GaugeManager(address(this)),
            flywheelGaugeWeightBooster,
            1 weeks,
            address(this)
        );

        baseV2Minter = new BaseV2Minter(
            // Vault
            address(bHermesToken),
            // Dao
            address(flywheelGaugeRewards),
            // Owner
            address(this)
        );

        flywheelGaugeRewards =
        new FlywheelGaugeRewards({_rewardToken: address(rewardToken),_owner:address(this), _gaugeToken:bHermesToken.gaugeWeight(),  _minter:baseV2Minter});

        baseV2Minter.initialize(flywheelGaugeRewards);

        uniswapV3GaugeFactory = new UniswapV3GaugeFactory(
            BaseV2GaugeManager(address(0)),
            bHermesToken.gaugeBoost(),
            uniswapV3Factory,
            nonfungiblePositionManager,
            flywheelGaugeRewards,
            bribesFactory,
            // Owner
            address(this)
        );

        // This is calling GaugeManager.addGauge(address), but why?
        vm.mockCall(address(0), abi.encodeWithSignature("addGauge(address)"), abi.encode(""));

        uniswapV3StakerContract = uniswapV3GaugeFactory.uniswapV3Staker();

        uniswapV3Staker = IUniswapV3Staker(address(uniswapV3StakerContract));
        vm.label(address(uniswapV3Staker), "uniswapV3Staker");

        vm.stopPrank();

        deal(address(DAI), USER1, 1_000_000e18);
        deal(address(USDC), USER1, 1_000_000e6);
        deal(address(rewardToken), USER2, 1_000_000e18);
    }

    function testOpenUniPosition() public {
        vm.startPrank(USER1, USER1);
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6});
        // Test contract holds the NFT
        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(this));
        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6});
        vm.stopPrank();

        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 50});

        vm.startPrank(USER2, USER2);
        // Someone will create the incentive to draw the liquidity to his project (USER2)
        emit log_named_uint("[testStake]: Computed Start: ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[testStake]: Pool: ", address(DAI_USDC_pool));
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        nonfungiblePositionManager.safeTransferFrom(address(this), address(uniswapV3Staker), tokenId);

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, address(this));
        assertEq(stakedTimestamp, block.timestamp);
    }

    function testClaimStakingRewards() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6});
        vm.stopPrank();

        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 50});

        vm.startPrank(USER2, USER2);

        emit log_named_uint("[TEST]: Computed start time (key): ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[TEST]: Pool address: ", address(DAI_USDC_pool));

        // Someone will create the incentive to draw the liquidity to his project (USER2)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        nonfungiblePositionManager.safeTransferFrom(address(this), address(uniswapV3Staker), tokenId);

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, address(this));
        assertEq(stakedTimestamp, block.timestamp);
        ////////////////////////////////////////////////////////////////////////

        vm.warp(block.timestamp + 1 weeks);

        (uint256 reward,) = uniswapV3Staker.getRewardInfo(key, tokenId);

        uniswapV3Staker.unstakeToken(tokenId);

        emit log_named_uint("[INFO] Rewards after unstaking: ", uniswapV3Staker.tokenIdRewards(tokenId));

        uniswapV3Staker.claimAllRewards(address(this));
    }

    function testShouldNotWithdrawForSomeoneElse() public {}
    ////////////////////////////////////////////////////////////////////
    //                            Utilities                           //
    ////////////////////////////////////////////////////////////////////

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token. For this example we are providing 1000 WETH and 1000 USDC in liquidity
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        TransferHelper.safeApprove(DAI, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(USDC, address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: DAI,
            token1: USDC,
            fee: poolFee,
            tickLower: -60,
            tickUpper: 60,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.

        if (amount0 < amount1ToMint) {
            TransferHelper.safeApprove(DAI, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(DAI, msg.sender, refund1);
        }

        if (amount1 < amount0ToMint) {
            TransferHelper.safeApprove(USDC, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(USDC, msg.sender, refund0);
        }
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (,, address token0, address token1,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
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
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }
}
