// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Boilerplate.sol";

contract BrokenRestake is Boilerplate, IERC721Receiver {
    uint256 tokenIdAlice;
    uint256 tokenIdBob;

    function setUp() public {
        initializeBoilerplate();

        // In HERMES deployment the owner will be set to BaseV2Minter
        // In this test ADMIN is set as a temporary owner just to mint
        // initial tokens to get the reward system rolling.
        rewardToken = new HERMES({_owner: ADMIN});

        vm.startPrank(ADMIN);
        rewardToken.mint(ALICE, 1_000e18);
        rewardToken.mint(BOB, 1_000e18);
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

        baseV2Minter = new BaseV2Minter({ _vault:address(bHermesToken), _dao: address(0), _owner: ADMIN });

        // Transfer ownership to BaseV2Minter to mimic real deployment
        vm.prank(ADMIN);
        rewardToken.transferOwnership(address(baseV2Minter));

        flywheelGaugeRewards =
        new FlywheelGaugeRewards({_rewardToken: address(rewardToken), _owner:ADMIN, _gaugeToken:bHermesToken.gaugeWeight(), _minter:baseV2Minter});

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

        deal(address(DAI), ALICE, 1_000e18);
        deal(address(USDC), ALICE, 1_000e6);
        deal(address(DAI), BOB, 1_000e18);
        deal(address(USDC), BOB, 1_000e6);

        vm.startPrank(ADMIN);
        gauge = createGaugeAndAddToGaugeBoost({_pool: DAI_USDC_pool, minWidth: 1});
        vm.stopPrank();

        vm.startPrank(ALICE);
        rewardToken.approve(address(bHermesToken), 500e18);
        bHermesToken.deposit(500e18, ALICE);
        bHermesToken.claimMultiple(500e18);
        bHermesToken.gaugeWeight().delegate(ALICE);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(500e18));
        vm.stopPrank();

        vm.startPrank(BOB);
        rewardToken.approve(address(bHermesToken), 500e18);
        bHermesToken.deposit(500e18, BOB);
        bHermesToken.claimMultiple(500e18);
        bHermesToken.gaugeWeight().delegate(BOB);
        bHermesToken.gaugeWeight().incrementGauge(address(gauge), uint112(500e18));
        vm.stopPrank();

        // newEpoch() only triggers reward accrual if previous epoch < new epoch
        // Since the whole setup is happening in the previous epoch, we need to
        // warp to the next epoch
        vm.warp(block.timestamp + 1 weeks);
        // This call will pull HERMES token rewards from the minter
        // and create the initial incentive
        gauge.newEpoch();

        // This is how incentive start time is calculated in createIncentiveFromGauge
        // This is also the start of the new week
        uint256 incentiveStartTime = IncentiveTime.computeEnd(block.timestamp);
        vm.warp(incentiveStartTime);
        // That's why newEpoch() can be called
        gauge.newEpoch();

        vm.startPrank(ALICE);
        (tokenIdAlice,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: ALICE});
        vm.stopPrank();

        vm.startPrank(BOB);
        (tokenIdBob,,,) = mintNewPosition({amount0ToMint: 1_000e18, amount1ToMint: 1_000e6, _recipient: BOB});
        vm.stopPrank();
    }

    function testRestake_RestakeIsNotPermissionless() public {
        vm.startPrank(ALICE);
        // 1.a Alice stakes her NFT (at incentive StartTime)
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        // 1.b Bob stakes his NFT (at incentive StartTime)
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks); // 2.a Warp to incentive end time
        gauge.newEpoch();                   // 2.b Queue minter rewards for the next cycle

        vm.startPrank(BOB);
        uniswapV3Staker.restakeToken(tokenIdBob); // 3.a Bob can restake his own token
        vm.stopPrank();

        // vm.startPrank(CHARLIE);
        // vm.expectRevert(bytes4(keccak256("NotCalledByOwner()")));
        // uniswapV3Staker.restakeToken(tokenIdAlice); // 3.b Charlie cannot restake Alice's token
        // vm.stopPrank();

        bytes memory functionCall1 = abi.encodeWithSignature(
            "restakeToken(uint256)",
            tokenIdAlice
        );
        bytes memory functionCall2 = abi.encodeWithSignature(
            "restakeToken(uint256)",
            tokenIdBob
        );

        bytes[] memory data = new bytes[](2);
        data[0] = functionCall1;
        data[1] = functionCall2;

        vm.startPrank(CHARLIE);
        address(uniswapV3Staker).call(abi.encodeWithSignature("multicall(bytes[])", data));
        vm.stopPrank();

        uint256 rewardsBob = uniswapV3Staker.rewards(BOB);
        uint256 rewardsAlice = uniswapV3Staker.rewards(ALICE);

        assertNotEq(rewardsBob, 0, "Bob should have rewards");
        assertEq(rewardsAlice, 0, "Alice should not have rewards");

        console.log("");
        console.log("=================");
        console.log("Bob's rewards   : %s", rewardsBob);
        console.log("Alice's rewards : %s", rewardsAlice);
        console.log("=================");
    }

    // Not an issue
    function testRestake_IncorrectIncentiveStartTime() public {
        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        // Warp to incentive end time
        vm.warp(block.timestamp + 1 weeks);
        // This call will queue minter rewards for the next cycle
        gauge.newEpoch();

        vm.prank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        vm.prank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);

        // A week of no staking, because there is no reward

        // Warp to incentive start time
        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.stakeToken(tokenIdBob);
        // uniswapV3Staker.restakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();
    }

    function testRestake_BobRewardsWhenAliceRestakes() public {
        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        // Warp to incentive end time
        vm.warp(block.timestamp + 1 weeks);
        // This call will queue minter rewards for the next cycle
        gauge.newEpoch();

        vm.prank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        vm.prank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);

        // A week of no staking, because there is no reward

        // Warp to incentive start time
        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.stakeToken(tokenIdBob);
        // uniswapV3Staker.restakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(ALICE);
        uniswapV3Staker.unstakeToken(tokenIdAlice);
        uniswapV3Staker.stakeToken(tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();

        uint256 bobRewardsAfterAliceRestakes = uniswapV3Staker.rewards(BOB);
        uint256 aliceRewardsAfterAliceRestakes = uniswapV3Staker.rewards(ALICE);

        console.log("--------------------------------------------------------------");
        console.log("Bob rewards after Alice restakes          : %s", bobRewardsAfterAliceRestakes);
        console.log("Alice rewards after Alice restakes        : %s", aliceRewardsAfterAliceRestakes);
        console.log("--------------------------------------------------------------");
    }

    function testRestake_BobRewardsAliceDoesNotRestake() public {
        vm.startPrank(ALICE);
        nonfungiblePositionManager.safeTransferFrom(ALICE, address(uniswapV3Staker), tokenIdAlice);
        vm.stopPrank();

        vm.startPrank(BOB);
        nonfungiblePositionManager.safeTransferFrom(BOB, address(uniswapV3Staker), tokenIdBob);
        vm.stopPrank();

        // Warp to incentive end time
        vm.warp(block.timestamp + 1 weeks);
        // This call will queue minter rewards for the next cycle
        gauge.newEpoch();

        vm.prank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);

        // A week of no staking, because there is no reward

        // Warp to incentive start time
        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(BOB);
        uniswapV3Staker.stakeToken(tokenIdBob);
        // uniswapV3Staker.restakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);
        gauge.newEpoch();

        vm.startPrank(BOB);
        uniswapV3Staker.unstakeToken(tokenIdBob);
        uniswapV3Staker.stakeToken(tokenIdBob);
        vm.stopPrank();

        uint256 bobRewardsAfterNoRestakeFromAlice = uniswapV3Staker.rewards(BOB);
        uint256 aliceRewardsAfterNoRestakeFromAlice = uniswapV3Staker.rewards(ALICE);

        console.log("--------------------------------------------------------------");
        console.log("Bob rewards after no restake from Alice   : %s", bobRewardsAfterNoRestakeFromAlice);
        console.log("Alice rewards after no restake from Alice : %s", aliceRewardsAfterNoRestakeFromAlice);
        console.log("--------------------------------------------------------------");
    }

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
            TransferHelper.safeTransfer(DAI, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(USDC, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(USDC, msg.sender, refund1);
        }
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
        // The following 3 lines has been added on top of the original code
        bHermesToken.gaugeWeight().addGauge(address(_gauge));
        bHermesToken.gaugeWeight().setMaxGauges(4);
        bHermesToken.gaugeWeight().setMaxDelegates(1);
    }

    // Create a Uniswap V3 Staker incentive
    function createIncentive(IUniswapV3Staker.IncentiveKey memory _key, uint256 amount) internal {
        uniswapV3Staker.createIncentive(_key, amount);
    }
}
