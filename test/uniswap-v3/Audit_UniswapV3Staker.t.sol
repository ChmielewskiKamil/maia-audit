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
        rewardToken.mint(CHARLIE, 10_000e18);
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

        deal(address(DAI), ALICE, 1_000_000e18);
        deal(address(USDC), ALICE, 1_000_000e6);
        deal(address(DAI), BOB, 1_000_000e18);
        deal(address(USDC), BOB, 1_000_000e6);
        
        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();
    }

    function testOpenUniPosition() public {
        vm.startPrank(ALICE, ALICE);
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        // Test contract holds the NFT
        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(this));
        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(ALICE);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(BOB, BOB);
        // Someone will create the incentive to draw the liquidity to his project (BOB)
        emit log_named_uint("[testStake]: Computed Start: ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[testStake]: Pool: ", address(DAI_USDC_pool));
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.prank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenId);

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, ALICE);
        assertEq(stakedTimestamp, block.timestamp);
    }

    function testStake_MultipleUsers() public {
        gauge.newEpoch();

        uint256 hermesBalanceAliceBefore = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceBobBefore = rewardToken.balanceOf(BOB);
        assertEq(hermesBalanceAliceBefore, 0);
        assertEq(hermesBalanceBobBefore, 0);

        // Alice's deposit will be 10x bigger than Bob's to showcase the difference in rewards.
        vm.startPrank(ALICE);
        (uint256 tokenIdAlice,,,) = mintNewPosition({amount0ToMint: 10_000e18, amount1ToMint: 10_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(BOB);
        (uint256 tokenIdBob,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: BOB});
        vm.stopPrank();

        vm.startPrank(CHARLIE);
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        console.log("Current timestamp: %s", block.timestamp);
        console.log("Incentive start time: %s", key.startTime);
        console.log("Incentive will start in ~%s hours", (key.startTime - block.timestamp) / 1 hours);
        vm.warp(key.startTime);
        
        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();
        
        vm.startPrank(BOB);
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdAlice), 0, "Rewards should be 0 at the beginning");
        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdBob), 0, "Rewards should be 0 at the beginning");

        // Warp to the incentive end time
        vm.warp(block.timestamp + 1 weeks);
        assertEq(key.startTime + 1 weeks, block.timestamp);

        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdAlice), 0, "Rewards should be 0 before unstaking");
        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdBob), 0, "Rewards should be 0 before unstaking");

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        vm.stopPrank();

        // vm.startPrank(BOB);
        // uniswapV3Staker.unstakeToken(tokenIdBob);
        // vm.stopPrank();

        uint256 hermesRewardAfterFirstStakeAlice = uniswapV3Staker.tokenIdRewards(tokenIdAlice);
        uint256 hermesRewardAfterFirstStakeBob = uniswapV3Staker.tokenIdRewards(tokenIdBob);
        console.log("[INFO] Alice's rewards: %s", hermesRewardAfterFirstStakeAlice);
        console.log("[INFO] Bob's rewards:   %s", hermesRewardAfterFirstStakeBob);

        assertGt(uniswapV3Staker.tokenIdRewards(tokenIdAlice), uniswapV3Staker.tokenIdRewards(tokenIdBob), "Alice should have more rewards than Bob");

        vm.startPrank(ALICE);
        uniswapV3Staker.claimAllRewards(ALICE);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.claimAllRewards(BOB);
        vm.stopPrank();

        uint256 hermesBalanceAfterFirstStakeAlice = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceAfterFirstStakeBob = rewardToken.balanceOf(BOB);

        assertEq(hermesBalanceAfterFirstStakeAlice, hermesBalanceAliceBefore + hermesRewardAfterFirstStakeAlice, "Alice should have received her rewards");
        assertEq(hermesBalanceAfterFirstStakeBob, hermesBalanceBobBefore + hermesRewardAfterFirstStakeBob, "Bob should have received his rewards");

        vm.startPrank(ALICE);
        rewardToken.approve(address(bHermesToken), rewardToken.balanceOf(ALICE));
        bHermesToken.deposit(rewardToken.balanceOf(ALICE), ALICE);
        bHermesToken.claimMultiple(bHermesToken.balanceOf(ALICE));
        bHermesToken.gaugeWeight().delegate(ALICE);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(bHermesToken.balanceOf(ALICE)));
        vm.stopPrank();
        
        // vm.startPrank(BOB);
        // rewardToken.approve(address(bHermesToken), rewardToken.balanceOf(BOB));
        // bHermesToken.deposit(rewardToken.balanceOf(BOB), BOB);
        // bHermesToken.claimMultiple(bHermesToken.balanceOf(BOB));
        // bHermesToken.gaugeWeight().delegate(BOB);
        // bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(bHermesToken.balanceOf(BOB)));
        // vm.stopPrank();

        uint256 hermesBalanceAfterFirstGaugeIncrementAlice = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceAfterFirstGaugeIncrementBob = rewardToken.balanceOf(BOB);
        assertEq(hermesBalanceAfterFirstGaugeIncrementAlice, 0);
        assertEq(hermesBalanceAfterFirstGaugeIncrementBob, 0);

        // The rewards are queued for the next cycle
        vm.warp(block.timestamp + 7 days);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.restakeToken(tokenIdBob);
        vm.stopPrank();
    }

    uint256 timestampStart;
    function testStake_weirdCycles() public {
        timestampStart = block.timestamp;
        uint256 gaugeEpochStart = gauge.epoch();
        uint256 minterActivePeriodStart = baseV2Minter.activePeriod();
        console.log("[INFO]   Current timestamp              : %s", timestampStart);
        console.log("[INFO]   Current gauge epoch            : %s", gaugeEpochStart);
        console.log("[INFO]   Current minter active period   : %s", minterActivePeriodStart);

        uint256 hermesBalanceAliceBefore = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceBobBefore = rewardToken.balanceOf(BOB);
        assertEq(hermesBalanceAliceBefore, 0);
        assertEq(hermesBalanceBobBefore, 0);

        // Alice's deposit will be 10x bigger than Bob's to showcase the difference in rewards.
        vm.startPrank(ALICE);
        (uint256 tokenIdAlice,,,) = mintNewPosition({amount0ToMint: 10_000e18, amount1ToMint: 10_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(BOB);
        (uint256 tokenIdBob,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: BOB});
        vm.stopPrank();

        vm.startPrank(CHARLIE);
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        console.log("[INFO]   Charlie's incentive start time : %s", key.startTime);
        console.log("[INFO]   Incentive will start in        : ~%s days", (key.startTime - block.timestamp) / 1 days);

        console.log("[STATUS] Warp to the incentive startTime");
        vm.warp(key.startTime);
        console.log("[INFO]   Days since test started        : ~%s days", (block.timestamp - timestampStart) / 1 days);
        
        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();
        
        vm.startPrank(BOB);
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        console.log("[STATUS] Alice and Bob: stake the positions...");

        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdAlice), 0, "Rewards should be 0 at the beginning");
        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdBob), 0, "Rewards should be 0 at the beginning");

        // Warp to the incentive end time
        vm.warp(block.timestamp + 1 weeks);
        assertEq(key.startTime + 1 weeks, block.timestamp);
        console.log("[STATUS] Warp to the incentive endTime");
        console.log("[INFO]   Days since test started        : ~%s days", (block.timestamp - timestampStart) / 1 days);

        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdAlice), 0, "Rewards should be 0 before unstaking");
        assertEq(uniswapV3Staker.tokenIdRewards(tokenIdBob), 0, "Rewards should be 0 before unstaking");

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        vm.stopPrank();

        console.log("[STATUS] Alice and Bob: unstake tokens...");

        uint256 hermesRewardAfterFirstStakeAlice = uniswapV3Staker.tokenIdRewards(tokenIdAlice);
        uint256 hermesRewardAfterFirstStakeBob = uniswapV3Staker.tokenIdRewards(tokenIdBob);
        console.log("[INFO]   Alice's rewards                : %s", hermesRewardAfterFirstStakeAlice);
        console.log("[INFO]   Bob's rewards                  : %s", hermesRewardAfterFirstStakeBob);

        assertGt(uniswapV3Staker.tokenIdRewards(tokenIdAlice), uniswapV3Staker.tokenIdRewards(tokenIdBob), "Alice should have more rewards than Bob");

        vm.startPrank(ALICE);
        uniswapV3Staker.claimAllRewards(ALICE);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.claimAllRewards(BOB);
        vm.stopPrank();

        console.log("[STATUS] Alice and Bob: claim rewards");

        uint256 hermesBalanceAfterFirstStakeAlice = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceAfterFirstStakeBob = rewardToken.balanceOf(BOB);

        assertEq(hermesBalanceAfterFirstStakeAlice, hermesBalanceAliceBefore + hermesRewardAfterFirstStakeAlice, "Alice should have received her rewards");
        assertEq(hermesBalanceAfterFirstStakeBob, hermesBalanceBobBefore + hermesRewardAfterFirstStakeBob, "Bob should have received his rewards");

        vm.startPrank(ALICE);
        rewardToken.approve(address(bHermesToken), rewardToken.balanceOf(ALICE));
        bHermesToken.deposit(rewardToken.balanceOf(ALICE), ALICE);
        bHermesToken.claimMultiple(bHermesToken.balanceOf(ALICE));
        bHermesToken.gaugeWeight().delegate(ALICE);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(bHermesToken.balanceOf(ALICE)));
        vm.stopPrank();
        
        vm.startPrank(BOB);
        rewardToken.approve(address(bHermesToken), rewardToken.balanceOf(BOB));
        bHermesToken.deposit(rewardToken.balanceOf(BOB), BOB);
        bHermesToken.claimMultiple(bHermesToken.balanceOf(BOB));
        bHermesToken.gaugeWeight().delegate(BOB);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(bHermesToken.balanceOf(BOB)));
        vm.stopPrank();

        console.log("[STATUS] Alice and Bob: deposit, claim weight and increment gauge");

        uint256 hermesBalanceAfterFirstGaugeIncrementAlice = rewardToken.balanceOf(ALICE);
        uint256 hermesBalanceAfterFirstGaugeIncrementBob = rewardToken.balanceOf(BOB);
        assertEq(hermesBalanceAfterFirstGaugeIncrementAlice, 0);
        assertEq(hermesBalanceAfterFirstGaugeIncrementBob, 0);

        // The unclaimed rewards are queued for the next cycle
        vm.warp(block.timestamp + 7 days);
        console.log("[STATUS] Warp 7 days");
        console.log("[INFO]   Days since test started        : ~%s days", (block.timestamp - timestampStart) / 1 days);
        console.log("[INFO]   Current gauge epoch            : %s", gauge.epoch());
        console.log("[STATUS] Calling newEpoch()");
        gauge.newEpoch();
        console.log("[INFO]   Updated gauge epoch            : %s", gauge.epoch());
        console.log("[INFO]   Updated minter period          : %s", baseV2Minter.activePeriod());
        uint256 newIncentiveStartTime = IncentiveTime.computeEnd(block.timestamp);
        console.log("[INFO]   Incentive created from gauge   : %s", newIncentiveStartTime);
        console.log("[INFO]   New incentive will start in    : %s days", (newIncentiveStartTime - block.timestamp) / 1 days);

        vm.warp(block.timestamp + 7 days);
        console.log("[STATUS Warp to the new incentive start time");
        console.log("[INFO]   Days since test started        : ~%s days", (block.timestamp - timestampStart) / 1 days);

        vm.startPrank(ALICE);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();
        console.log("[STATUS] Alice: stake token");

        vm.warp(block.timestamp + 7 days);
        console.log("[STATUS] Warp to the new incentive end time");
        console.log("[INFO]   Days since test started        : ~%s days", (block.timestamp - timestampStart) / 1 days);

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        vm.stopPrank();
        console.log("[STATUS] Alice: unstake token");

        console.log("[STATUS] Calling newEpoch()");
        gauge.newEpoch();
        console.log("[INFO]   Updated gauge epoch            : %s", gauge.epoch());
        console.log("[INFO]   Updated minter period          : %s", baseV2Minter.activePeriod());
        uint256 newIncentive2StartTime = IncentiveTime.computeEnd(block.timestamp);
        console.log("[INFO]   Incentive created from gauge   : %s", newIncentive2StartTime);
        console.log("[INFO]   New incentive will start in    : %s days", (newIncentive2StartTime - block.timestamp) / 1 days);

        vm.warp(block.timestamp + 7 days);
        console.log("[STATUS] Warp to the new incentive start time");

        vm.startPrank(ALICE);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();
        console.log("[STATUS] Alice: stake token");
    }

    function testClaimStakingRewards() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(ALICE);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        emit log_named_address("[TEST] Token owner: ", nonfungiblePositionManager.ownerOf(tokenId));
        vm.stopPrank();

        vm.startPrank(BOB);

        emit log_named_uint("[TEST]: Computed start time (key): ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[TEST]: Pool address: ", address(DAI_USDC_pool));

        // Someone will create the incentive to draw the liquidity to his project (BOB)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, ALICE);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        vm.warp(block.timestamp + 1 weeks);

        // (uint256 reward,) = uniswapV3Staker.getRewardInfo(key, tokenId);

        vm.prank(ALICE);
        uniswapV3Staker.unstakeToken(tokenId);

        emit log_named_uint("[INFO] Rewards after unstaking: ", uniswapV3Staker.tokenIdRewards(tokenId));

        uniswapV3Staker.claimAllRewards(address(this));
    }

    function testRestake_SimpleRestake() public {
        //////////////// THIS IS THE SAME AS IN TESTSTAKE //////////////////////
        vm.startPrank(ALICE);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(ALICE);
        // User needs to deposit (burn) HERMES for bHermes to later claim weight
        rewardToken.approve(address(bHermesToken), 1_000e18);
        bHermesToken.deposit(1_000e18, ALICE);
        bHermesToken.claimMultiple(1_000e18);
        bHermesToken.gaugeWeight().delegate(ALICE);

        // Allocate claimed weight to the gauge, so that rewards are distributed to the gauge
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), 100e18);
        vm.stopPrank();

        vm.startPrank(BOB);
        // Someone will create the incentive to draw the liquidity to his project (BOB)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, ALICE);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        gauge.newEpoch();

        vm.warp(block.timestamp + 7 days);

        vm.startPrank(ALICE);
        uniswapV3Staker.restakeToken(tokenId);
        vm.stopPrank();

        vm.prank(ALICE);
        uniswapV3Staker.claimAllRewards(ALICE);
        // uniswapV3Staker.endIncentive(key);
    }

    // Confirmed Finding
    function testRestake_AnyoneCanRestakeAfterIncentiveEnds() public {
        //////////////// THIS IS THE SAME //////////////////////
        vm.startPrank(ALICE);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        emit log_named_address("[TEST] Token owner: ", nonfungiblePositionManager.ownerOf(tokenId));
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(BOB);

        emit log_named_uint("[TEST]: Computed start time (key): ", IncentiveTime.computeEnd(block.timestamp));
        emit log_named_address("[TEST]: Pool address: ", address(DAI_USDC_pool));

        // Someone will create the incentive to draw the liquidity to his project (BOB)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, ALICE);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        // We will warp the time past the incentive end time
        vm.warp(block.timestamp + 8 days);

        vm.startPrank(BOB);
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
        vm.startPrank(BOB);
        uniswapV3Staker.restakeToken(tokenId);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);

        vm.prank(ALICE);
        uniswapV3Staker.unstakeToken(tokenId);

        vm.prank(ALICE);
        uniswapV3Staker.claimAllRewards(ALICE);
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

        vm.startPrank(ALICE);
        rewardToken.approve(address(bHermesToken), 10_000e18);
        bHermesToken.deposit(10_000e18, ALICE);
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

        // rewardToken.mint(ALICE, 100_000e18);
        // deal(address(rewardToken), ALICE, 100_000e18);
        vm.startPrank(ALICE);
        rewardToken.approve(address(bHermesToken), 10_000e18);
        bHermesToken.deposit(10_000e18, ALICE);
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

        vm.startPrank(BOB, BOB);
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
        vm.startPrank(ALICE);
        // User needs to have a UniV3 position for staking (ex. DAI/USDC)
        (uint256 tokenId,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        gauge2 = createGaugeAndAddToGaugeBoost({_pool: mockPool2, minWidth: 1});
        gauge3 = createGaugeAndAddToGaugeBoost({_pool: mockPool3, minWidth: 1});
        gauge4 = createGaugeAndAddToGaugeBoost({_pool: mockPool4, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(ALICE);
        // User needs to deposit (burn) HERMES for bHermes to later claim weight
        rewardToken.approve(address(bHermesToken), 1_000e18);
        bHermesToken.deposit(1_000e18, ALICE);
        bHermesToken.claimMultiple(1_000e18);
        bHermesToken.gaugeWeight().delegate(ALICE);

        // Allocate claimed weight to the gauge, so that rewards are distributed to the gauge
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), 10e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge2), 20e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge3), 30e18);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge4), 40e18);
        vm.stopPrank();

        vm.startPrank(BOB);
        // Someone will create the incentive to draw the liquidity to his project (BOB)
        key = IUniswapV3Staker.IncentiveKey({pool: DAI_USDC_pool, startTime: IncentiveTime.computeEnd(block.timestamp)});
        rewardToken.approve(address(uniswapV3Staker), 10_000e18);
        createIncentive({_key: key, amount: 10_000e18});
        vm.stopPrank();

        vm.warp(key.startTime);

        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenId);
        vm.stopPrank();

        assertEq(nonfungiblePositionManager.ownerOf(tokenId), address(uniswapV3Staker));
        (address owner,,, uint256 stakedTimestamp) = uniswapV3Staker.deposits(tokenId);
        assertEq(owner, ALICE);
        assertEq(stakedTimestamp, block.timestamp);

        ////////////////////////////////////////////////////////////////////////

        flywheelGaugeRewards.queueRewardsForCycle();

        vm.warp(block.timestamp + 1 weeks);

        // flywheelGaugeRewards.queueRewardsForCyclePaginated(4);

        //
        vm.warp(block.timestamp + 7 days);
        //
        //
        // vm.startPrank(ALICE);
        // uniswapV3Staker.restakeToken(tokenId);
        // vm.stopPrank();
        //
        // vm.prank(ALICE);
        // uniswapV3Staker.claimAllRewards(ALICE);
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
