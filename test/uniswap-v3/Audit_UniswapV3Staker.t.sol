// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../Boilerplate.sol";

contract Audit_UniswapV3Staker is Boilerplate, IERC721Receiver {
    function setUp() public {
        initializeBoilerplate();

        // In HERMES deployment the owner will be set to BaseV2Minter
        // In this test ADMIN is set as a temporary owner just to mint
        // initial tokens to get the reward system rolling.
        rewardToken = new HERMES({_owner: ADMIN});

        vm.startPrank(ADMIN);
        rewardToken.mint(USER1, 1_000e18);
        rewardToken.mint(USER2, 10_000e18);
        vm.stopPrank();

        bHermesToken =
        new bHermes({ _hermes: rewardToken, _owner: ADMIN, _gaugeCycleLength: 1 weeks, _incrementFreezeWindow: 12 hours });

        flywheelGaugeWeightBooster = new FlywheelBoosterGaugeWeight({ _bHermesGauges: bHermesToken.gaugeWeight() });

        bribesFactory = new BribesFactory(
            BaseV2GaugeManager(address(this)),
            flywheelGaugeWeightBooster,
            1 weeks,
            ADMIN
        );

        baseV2Minter = new BaseV2Minter(
            // Vault
            address(bHermesToken),
            // Dao
            address(flywheelGaugeRewards),
            // Owner
            ADMIN
        );

        // Ownership is transferred to the BaseV2Minter to mimic the real deployment
        vm.prank(ADMIN);
        rewardToken.transferOwnership(address(baseV2Minter));

        flywheelGaugeRewards =
        new FlywheelGaugeRewards({_rewardToken: address(rewardToken), _owner:ADMIN, _gaugeToken:bHermesToken.gaugeWeight(),  _minter:baseV2Minter});

        baseV2Minter.initialize(flywheelGaugeRewards);

        uniswapV3GaugeFactory = new UniswapV3GaugeFactory(
            BaseV2GaugeManager(address(0)),
            bHermesToken.gaugeBoost(),
            uniswapV3Factory,
            nonfungiblePositionManager,
            flywheelGaugeRewards,
            bribesFactory,
            // Owner
            ADMIN
        );

        vm.mockCall(address(0), abi.encodeWithSignature("addGauge(address)"), abi.encode(""));

        uniswapV3StakerContract = uniswapV3GaugeFactory.uniswapV3Staker();

        uniswapV3Staker = IUniswapV3Staker(address(uniswapV3StakerContract));

        deal(address(DAI), USER1, 1_000_000e18);
        deal(address(USDC), USER1, 1_000_000e6);
    }

    function testOpenUniPosition() public {
        vm.startPrank(USER1, USER1);
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        // Test contract holds the NFT
        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(this));
        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(USER2, USER2);
        // Someone will create the incentive to draw the liquidity to his project (USER2)
        emit log_named_uint("[testStake]: Computed Start: ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[testStake]: Pool: ", address(DAI_USDC_pool));
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.prank(USER1);
        nonfungiblePositionManager.safeTransferFrom(USER1, address(uniswapV3Staker), tokenId);

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, USER1);
        assertEq(stakedTimestamp, block.timestamp);
    }

    function testClaimStakingRewards() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        emit log_named_address("[TEST] Token owner: ", nonfungiblePositionManager.ownerOf(tokenId));
        vm.stopPrank();

        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});

        vm.startPrank(USER2);

        emit log_named_uint("[TEST]: Computed start time (key): ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[TEST]: Pool address: ", address(DAI_USDC_pool));

        // Someone will create the incentive to draw the liquidity to his project (USER2)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(USER1);
        nonfungiblePositionManager.safeTransferFrom(USER1, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, USER1);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        vm.warp(block.timestamp + 1 weeks);

        // (uint256 reward,) = uniswapV3Staker.getRewardInfo(key, tokenId);

        vm.prank(USER1);
        uniswapV3Staker.unstakeToken(tokenId);

        emit log_named_uint("[INFO] Rewards after unstaking: ", uniswapV3Staker.tokenIdRewards(tokenId));

        uniswapV3Staker.claimAllRewards(address(this));
    }

    function testRestake_SimpleRestake() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(USER1);
        // User needs to deposit (burn) HERMES for bHermes to later claim weight
        rewardToken.approve(address(bHermesToken), 1_000e18);
        bHermesToken.deposit(1_000e18, USER1);
        bHermesToken.claimMultiple(1_000e18);
        bHermesToken.gaugeWeight().delegate(USER1);

        // Allocate claimed weight to the gauge, so that rewards are distributed to the gauge
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), 100e18);
        vm.stopPrank();

        vm.startPrank(USER2);
        // Someone will create the incentive to draw the liquidity to his project (USER2)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(USER1);
        nonfungiblePositionManager.safeTransferFrom(USER1, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, USER1);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        gauge.newEpoch();

        vm.warp(block.timestamp + 7 days);

        vm.startPrank(USER1);
        uniswapV3Staker.restakeToken(tokenId);
        vm.stopPrank();

        vm.prank(USER1);
        uniswapV3Staker.claimAllRewards(USER1);
        // uniswapV3Staker.endIncentive(key);
    }

    // Confirmed Finding
    function testRestake_AnyoneCanRestakeAfterIncentiveEnds() public {
        //////////////// THIS IS THE SAME //////////////////////
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        emit log_named_address("[TEST] Token owner: ", nonfungiblePositionManager.ownerOf(tokenId));
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(USER2);

        emit log_named_uint("[TEST]: Computed start time (key): ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[TEST]: Pool address: ", address(DAI_USDC_pool));

        // Someone will create the incentive to draw the liquidity to his project (USER2)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(USER1);
        nonfungiblePositionManager.safeTransferFrom(USER1, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, USER1);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        // We will warp the time past the incentive end time
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(USER2);
        // It is not possible to restake if new incentive program has not been started. The calculated incentiveId,
        // will use the timestamp of the new period and it will be different. RestakeToken would fail with nonExistentIncentive
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        // THE ISSUE IS ON THE FOLLOWING LINE
        vm.expectRevert(bytes4(keccak256("NotCalledByOwner()")));
        // According to the comment in the UniswapV3Staker _unstakeToken function,
        // anyone should be able to restake the token after the incentive ends.
        vm.startPrank(USER2);
        uniswapV3Staker.restakeToken(tokenId);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);

        vm.prank(USER1);
        uniswapV3Staker.unstakeToken(tokenId);

        vm.prank(USER1);
        uniswapV3Staker.claimAllRewards(USER1);
    }

    function testMinter_UpdatePeriodFasterThanExpected() public {
        // For repeatability we are pinning it down to a specific timestamp
        // anvil --fork-block-number 105191210
        assertEq(block.timestamp, 1687805618);
        emit log_named_uint("[INFO] Block timestamp at test start: ", block.timestamp);
        emit log("[INFO] Mon, 26 Jun 2023 18:53:38 +0000");
        emit log("");

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(USER1);
        rewardToken.approve(address(bHermesToken), 10_000e18);
        bHermesToken.deposit(10_000e18, USER1);
        vm.stopPrank();

        uint256 activePeriodBefore1 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyBefore1 = baseV2Minter.circulatingSupply();

        emit log_named_uint("[INFO] Minter active period at test start: ", activePeriodBefore1);
        emit log("[INFO] Thu, 22 Jun 2023 00:00:00 +0000");

        // emit log_named_uint("[INFO] Minter HERMES circulating supply at test start: ", circulatingSupplyBefore1);

        emit log("");
        emit log("[STATUS] Calling update period immediately after initialization...");
        baseV2Minter.updatePeriod();
        emit log("");

        uint256 activePeriodAfter1 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyAfter1 = baseV2Minter.circulatingSupply();

        emit log_named_uint("[INFO] Minter active period after updating period: ", activePeriodAfter1);
        emit log("[INFO] Thu, 22 Jun 2023 00:00:00 +0000");
        // emit log_named_uint("[INFO] Minter HERMES circulating supply after updating period: ", circulatingSupplyAfter1);
        console.log("[TEST] Is period before == period after? ", activePeriodBefore1 == activePeriodAfter1);

        // Calling update period before 7 days have passed should have no effect
        assertEq(activePeriodBefore1, activePeriodAfter1);
        assertEq(circulatingSupplyBefore1, circulatingSupplyAfter1);

        emit log("");
        emit log("[STATUS] WARPING 2 days into the future...");
        emit log("[INFO] Time now: Wed, 28 Jun 2023 18:53:38 +0000");
        // emit log_named_uint("NOW + 2 days", block.timestamp + 2 days);
        vm.warp(block.timestamp + 2 days);

        uint256 activePeriodBefore2 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyBefore2 = baseV2Minter.circulatingSupply();

        baseV2Minter.updatePeriod();

        uint256 activePeriodAfter2 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyAfter2 = baseV2Minter.circulatingSupply();

        console.log("[TEST] Is period2 before == period2 after? ", activePeriodBefore2 == activePeriodAfter2);
        assertEq(activePeriodBefore2, activePeriodAfter2);
        assertEq(circulatingSupplyBefore2, circulatingSupplyAfter2);
    }

    function testMinter_NewEpoch() public {
        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        // rewardToken.mint(USER1, 100_000e18);
        // deal(address(rewardToken), USER1, 100_000e18);
        vm.startPrank(USER1);
        rewardToken.approve(address(bHermesToken), 10_000e18);
        bHermesToken.deposit(10_000e18, USER1);
        vm.stopPrank();

        emit log("==== testMinter_UpdatePeriodFasterThanExpected ====");
        uint256 activePeriodBefore1 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyBefore1 = baseV2Minter.circulatingSupply();
        emit log_named_uint("[TEST] Minter active period at test start: ", activePeriodBefore1);
        emit log_named_uint("[TEST] Minter HERMES circulating supply at test start: ", circulatingSupplyBefore1);

        emit log("[STATUS] Calling update period without waiting 7 days...");
        baseV2Minter.updatePeriod();

        uint256 activePeriodAfter1 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyAfter1 = baseV2Minter.circulatingSupply();
        emit log_named_uint("[TEST] Minter active period after updating period: ", activePeriodAfter1);
        emit log_named_uint("[TEST] Minter HERMES circulating supply after updating period: ", circulatingSupplyAfter1);

        // Calling update period before 7 days have passed should have no effect
        assertEq(activePeriodBefore1, activePeriodAfter1);
        assertEq(circulatingSupplyBefore1, circulatingSupplyAfter1);

        emit log("[STATUS] Warp 7 days in the future...");
        vm.warp(block.timestamp + 7 days);

        uint256 activePeriodBefore2 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyBefore2 = baseV2Minter.circulatingSupply();

        vm.startPrank(USER2, USER2);
        gauge.newEpoch();
        // baseV2Minter.updatePeriod();
        vm.stopPrank();

        uint256 activePeriodAfter2 = baseV2Minter.activePeriod();
        uint256 circulatingSupplyAfter2 = baseV2Minter.circulatingSupply();

        assertNotEq(activePeriodBefore2, activePeriodAfter2);
        assertNotEq(circulatingSupplyBefore2, circulatingSupplyAfter2);
    }

    function testRewards_DOSWithPaginatedQueue() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(USER1);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: USER1});
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        gauge2 = createGaugeAndAddToGaugeBoost({_pool: mockPool2, minWidth: 1});
        gauge3 = createGaugeAndAddToGaugeBoost({_pool: mockPool3, minWidth: 1});
        gauge4 = createGaugeAndAddToGaugeBoost({_pool: mockPool4, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(USER1);
        // User needs to deposit (burn) HERMES for bHermes to later claim weight
        rewardToken.approve(address(bHermesToken), 1_000e18);
        bHermesToken.deposit(1_000e18, USER1);
        bHermesToken.claimMultiple(1_000e18);
        bHermesToken.gaugeWeight().delegate(USER1);

        // Allocate claimed weight to the gauge, so that rewards are distributed to the gauge
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), 10e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge2), 20e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge3), 30e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge4), 40e18);
        vm.stopPrank();

        vm.startPrank(USER2);
        // Someone will create the incentive to draw the liquidity to his project (USER2)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(USER1);
        nonfungiblePositionManager.safeTransferFrom(USER1, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, USER1);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        flywheelGaugeRewards.queueRewardsForCycle();

        vm.warp(block.timestamp + 1 weeks);

        // flywheelGaugeRewards.queueRewardsForCyclePaginated(4);

        //
        vm.warp(block.timestamp + 7 days);
        //
        //
        // vm.startPrank(USER1);
        // uniswapV3Staker.restakeToken(tokenId);
        // vm.stopPrank();
        //
        // vm.prank(USER1);
        // uniswapV3Staker.claimAllRewards(USER1);
        // uniswapV3Staker.endIncentive(key);
    }

    function testGaugeRewards_PaginatedAndNonPaginated() public {}

    ////////////////////////////////////////////////////////////////////
    //                            Utilities                           //
    ////////////////////////////////////////////////////////////////////

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token. For this example we are providing 1000 WETH and 1000 USDC in liquidity
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, address _recipient)
        public
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        TransferHelper.safeApprove(DAI, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(USDC, address(nonfungiblePositionManager), amount1ToMint);

        // Current tick -276325
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: DAI,
            token1: USDC,
            fee: poolFee,
            tickLower: -276326,
            tickUpper: -276324,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: _recipient,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.

        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(DAI, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            emit log_named_uint("[TEST] DAI Refund amount: ", refund0);
            emit log_named_address("[TEST] Refunding DAI to the address: ", msg.sender);
            TransferHelper.safeTransfer(DAI, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(USDC, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            emit log_named_uint("[TEST] DAI Refund amount: ", refund1);
            emit log_named_address("[TEST] Refunding DAI to the address: ", msg.sender);
            TransferHelper.safeTransfer(USDC, msg.sender, refund1);
        }
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        (,, address token0, address token1,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        assertEq(token0, DAI, "Token0 should be DAI");
        assertEq(token1, USDC, "Token1 should be USDC");
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
        bHermesToken.gaugeWeight().addGauge(address(_gauge));
        bHermesToken.gaugeWeight().setMaxGauges(4);
        bHermesToken.gaugeWeight().setMaxDelegates(1);
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
