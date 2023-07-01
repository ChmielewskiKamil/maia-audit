// SPDX-License-Identifier: MIT
// Rewards logic inspired by Uniswap V3 Contracts (Uniswap/v3-staker/contracts/UniswapV3Staker.sol)
pragma solidity ^0.8.0;

import {Test, console2 as console} from "forge-std/Test.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IUniswapV3GaugeFactory} from "@gauges/interfaces/IUniswapV3GaugeFactory.sol";
import {UniswapV3Gauge} from "@gauges/UniswapV3Gauge.sol";
import {bHermesBoost} from "@hermes/tokens/bHermesBoost.sol";

import {IncentiveId} from "./libraries/IncentiveId.sol";
import {IncentiveTime} from "./libraries/IncentiveTime.sol";
import {NFTPositionInfo} from "./libraries/NFTPositionInfo.sol";
import {RewardMath} from "./libraries/RewardMath.sol";

import {IUniswapV3Staker} from "./interfaces/IUniswapV3Staker.sol";

/* @audit Make sure that there is no way to cheat the minimum range (width?) - the ticks 
* According to the docs https://v2-docs.maiadao.io/protocols/Hermes/overview/gauges/uni-v3
* Users with concentrated liquidty would be able to gain most of the emissions. */
/* @audit Investigate Multicallable */
/// @title Uniswap V3 Staker Interface with bHermes Boost.
contract UniswapV3Staker is IUniswapV3Staker, Multicallable, Test {
    using SafeTransferLib for address;
    event Audit_IncentiveId (bytes32 incentiveId);

    /*//////////////////////////////////////////////////////////////
                        UNISWAP V3 STAKER STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Staker
    mapping(address => IUniswapV3Pool) public gaugePool;

    /// @inheritdoc IUniswapV3Staker
    mapping(IUniswapV3Pool => UniswapV3Gauge) public gauges;

    /// @inheritdoc IUniswapV3Staker
    mapping(IUniswapV3Pool => address) public bribeDepots;

    /// @inheritdoc IUniswapV3Staker
    mapping(IUniswapV3Pool => uint24) public poolsMinimumWidth;

    /// @inheritdoc IUniswapV3Staker
    mapping(bytes32 => Incentive) public override incentives;

    /// @inheritdoc IUniswapV3Staker
    mapping(uint256 => Deposit) public override deposits;

    /// @notice stakes[user][pool] => tokenId of attached position of user per pool
    mapping(address => mapping(IUniswapV3Pool => uint256)) private _userAttachements;

    /// @dev stakes[tokenId][incentiveHash] => Stake
    mapping(uint256 => mapping(bytes32 => Stake)) private _stakes;

    /* @info This thing holds an information: to which incentive program is the NFT attached to
    * For ex. stakedIncentiveKey[MyNFT] will return the incentive key which describes the incentive program */
    /// @dev stakedIncentives[tokenId] => incentiveIds
    mapping(uint256 => IncentiveKey) private stakedIncentiveKey;

    /// @inheritdoc IUniswapV3Staker
    function stakes(uint256 tokenId, bytes32 incentiveId)
        public
        view
        override
        returns (uint160 secondsPerLiquidityInsideInitialX128, uint128 liquidity)
    {
        Stake storage stake = _stakes[tokenId][incentiveId];
        secondsPerLiquidityInsideInitialX128 = stake.secondsPerLiquidityInsideInitialX128;
        liquidity = stake.liquidityNoOverflow;
        if (liquidity == type(uint96).max) {
            liquidity = stake.liquidityIfOverflow;
        }
    }

    /// @inheritdoc IUniswapV3Staker
    function userAttachements(address user, IUniswapV3Pool pool) external view override returns (uint256) {
        return hermesGaugeBoost.isUserGauge(user, address(gauges[pool])) ? _userAttachements[user][pool] : 0;
    }

    /// @inheritdoc IUniswapV3Staker
    mapping(address => uint256) public override rewards;

    /// @inheritdoc IUniswapV3Staker
    mapping(uint256 => uint256) public tokenIdRewards;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Uniswap V3 Gauge Factory
    IUniswapV3GaugeFactory public immutable uniswapV3GaugeFactory;

    /// @inheritdoc IUniswapV3Staker
    IUniswapV3Factory public immutable override factory;

    /// @inheritdoc IUniswapV3Staker
    INonfungiblePositionManager public immutable override nonfungiblePositionManager;

    /// @inheritdoc IUniswapV3Staker
    uint256 public immutable override maxIncentiveStartLeadTime;

    /// @inheritdoc IUniswapV3Staker
    address public immutable minter;

    /// @inheritdoc IUniswapV3Staker
    address public immutable hermes;

    /// @inheritdoc IUniswapV3Staker
    bHermesBoost public immutable hermesGaugeBoost;

    /* @audit-ok Is the `address _minter` the `BaseV2Minter`?
    * Probably yes, according to the interface: 
    * "It's the address to send undistributed rewards to".
    * What are undistributed rewards then? Are there distributed rewards? 
    *
    * Minter mints HERMES tokens for rewards, after the incentive ends, 
    * the undistributed rewards go back to minter */
    /// @param _factory the Uniswap V3 factory
    /// @param _nonfungiblePositionManager the NFT position manager contract address
    /// @param _maxIncentiveStartLeadTime the max duration of an incentive in seconds
    constructor(
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        IUniswapV3GaugeFactory _uniswapV3GaugeFactory,
        bHermesBoost _hermesGaugeBoost,
        uint256 _maxIncentiveStartLeadTime,
        address _minter,
        address _hermes
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        maxIncentiveStartLeadTime = _maxIncentiveStartLeadTime;
        uniswapV3GaugeFactory = _uniswapV3GaugeFactory;
        hermesGaugeBoost = _hermesGaugeBoost;
        minter = _minter;
        hermes = _hermes;
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE INCENTIVE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Staker
    function createIncentiveFromGauge(uint256 reward) external {
        emit log("");
        emit log("==== UniswapV3Staker.createIncentiveFromGauge ====");
        if (reward <= 0) revert IncentiveRewardMustBePositive();

        /* @audit-ok Shouldn't this use computeStart? This is fcked for sure. 
        * It is okay, when creating incentive from the gauge the start time of the next incentive
        * is the end time of the previous one. */
        /* @audit-issue I've changed it to computeStart for testing */
        uint96 startTime = IncentiveTime.computeStart(block.timestamp);

        console.log("[INFO] Computed incentive start time is: %s, which is ~%s hours from current timestamp: %s.", startTime, (startTime - block.timestamp) / 1 hours, block.timestamp);

        /* @audit-ok Who is supposed to be msg.sender for this function? 
        * gaugePool returns the pool addr for a given gauge. 
        * It means that it is supposed to be called by the gauge */

        /* @audit Would it be possible to add EOA to the gaugePool? 
        * Like: msg.sender is mee and the returned pool is an arbitrary address.
        * The question is: What modifies the gaugePool? */
        IUniswapV3Pool pool = gaugePool[msg.sender];

        if (address(pool) == address(0)) revert IncentiveCallerMustBeRegisteredGauge();

        IncentiveKey memory key = IncentiveKey({startTime: startTime, pool: pool});
        bytes32 incentiveId = IncentiveId.compute(key);

        incentives[incentiveId].totalRewardUnclaimed += reward;

        /* @audit-ok This transfers HERMES tokens from the gauge to the staker contract.
        * How does the gauge get HERMES tokens in the first place? 
        * It gets them from the FlywheelGaugeRewards, which got the tokens from BaseMinterV2 */
        hermes.safeTransferFrom(msg.sender, address(this), reward);

        emit IncentiveCreated(pool, startTime, reward);
        emit log("---- createIncentiveFromGauge END ----");
    }

    /* @audit-ok How do you get an incentive key?
    * This is not a secret info, it's just the pool and incentive program start time.
    * Anyone can create such program, it requires sending some HERMES tokens as rewards
    * for participants. */
    /// @inheritdoc IUniswapV3Staker
    function createIncentive(IncentiveKey memory key, uint256 reward) external {
        emit log("");
        emit log("==== UniswapV3Staker.createIncentive ====");
        if (reward <= 0) revert IncentiveRewardMustBePositive();

        uint96 startTime = IncentiveTime.computeStart(key.startTime);

        emit log_named_uint("[CALC] Computed incentive start time: ", startTime);
        emit log("It has to match the start time from the key.");

        if (startTime != key.startTime) revert IncentiveStartTimeNotAtEndOfAnEpoch();

        if (startTime <= block.timestamp) revert IncentiveStartTimeMustBeNowOrInTheFuture();
        if (startTime - block.timestamp > maxIncentiveStartLeadTime) {
            revert IncentiveStartTimeTooFarIntoFuture();
        }

        if (address(gauges[key.pool]) == address(0)) {
            revert IncentiveCannotBeCreatedForPoolWithNoGauge();
        }

        bytes32 incentiveId = IncentiveId.compute(key);

        emit log_named_bytes32("[INFO] Computed incentiveId", incentiveId);

        incentives[incentiveId].totalRewardUnclaimed += reward;

        hermes.safeTransferFrom(msg.sender, address(this), reward);

        emit IncentiveCreated(key.pool, startTime, reward);
        emit log("----------------------------------------");
    }

    /*//////////////////////////////////////////////////////////////
                            END INCENTIVE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Staker
    function endIncentive(IncentiveKey memory key) external returns (uint256 refund) {
        emit log("");
        emit log("==== UniswapV3Staker.endIncentive ====");
        emit log_named_uint("[INFO] Computed incentive end time: ", IncentiveTime.getEnd(key.startTime));
        emit log_named_uint("[INFO] Current block timestamp: ", block.timestamp);

        if (block.timestamp < IncentiveTime.getEnd(key.startTime)) {
            revert EndIncentiveBeforeEndTime();
        }

        bytes32 incentiveId = IncentiveId.compute(key);

        Incentive storage incentive = incentives[incentiveId];

        refund = incentive.totalRewardUnclaimed;
        emit log_named_uint("[INFO] Total reward unclaimed: ", refund);

        if (refund == 0) revert EndIncentiveNoRefundAvailable();

        emit log_named_uint("[INFO] Number of remaining stakes: ", incentive.numberOfStakes);
        if (incentive.numberOfStakes > 0) revert EndIncentiveWhileStakesArePresent();

        // issue the refund
        incentive.totalRewardUnclaimed = 0;

        emit log_named_uint("[INFO] Minter balance before refund: ", hermes.balanceOf(minter));
        emit log("[STATUS] SafeTransfer refund to minter...");

        hermes.safeTransfer(minter, refund);

        emit log_named_uint("[INFO] Minter balance after refund: ", hermes.balanceOf(minter));

        /* @audit What does that mean? */
        // note we never clear totalSecondsClaimedX128
        emit IncentiveEnded(incentiveId, refund);
        emit log("----------------------------------------");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok Why the first param does not have a name?
    * From what I see this is a common practice on the onERC721Receiver, 
    * when you don't need a param but need to define it just so the selector is correct. */
    /// @dev Upon receiving a Uniswap V3 ERC721, create the token deposit and
    ///      _stakes in current incentive setting owner to `from`.
    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        emit log("==== UniV3Staker.onERC721Received ====");
        /* @audit-confirmed GAS not caught by the bot
        * Why is this assigning it to a local variable instead of using address(nonfungiblePositionManager)? 
        * Probably a gas optimization to reduce storage loads 
        * Why using it later directly then? 
        *
        * Removing local variable and using the nonfungiblePositionManager directly saves 5 gas on each deposit
        * Version 2 is the cheapest
        
        1. This is the current version
        | src/uni-v3-staker/UniswapV3Staker.sol:UniswapV3Staker contract |                 |        |        |        |         |
        |----------------------------------------------------------------|-----------------|--------|--------|--------|---------|
        | Deployment Cost                                                | Deployment Size |        |        |        |         |
        | 4564115                                                        | 23398           |        |        |        |         |
        | Function Name                                                  | min             | avg    | median | max    | # calls |
        | createIncentive                                                | 54228           | 54228  | 54228  | 54228  | 1       |
        | deposits                                                       | 698             | 698    | 698    | 698    | 1       |
        | onERC721Received                                               | 235867          | 235867 | 235867 | 235867 | 1       |
        | updateGauges                                                   | 97735           | 97735  | 97735  | 97735  | 1       |

                2. This is the simplified version with no local variable
        | src/uni-v3-staker/UniswapV3Staker.sol:UniswapV3Staker contract |                 |        |        |        |         |
        |----------------------------------------------------------------|-----------------|--------|--------|--------|---------|
        | Deployment Cost                                                | Deployment Size |        |        |        |         |
        | 4563715                                                        | 23396           |        |        |        |         |
        | Function Name                                                  | min             | avg    | median | max    | # calls |
        | createIncentive                                                | 54228           | 54228  | 54228  | 54228  | 1       |
        | deposits                                                       | 698             | 698    | 698    | 698    | 1       |
        | onERC721Received                                               | 235862          | 235862 | 235862 | 235862 | 1       |
        | updateGauges                                                   | 97735           | 97735  | 97735  | 97735  | 1       |

                3. This is the version where local variable is used in both places
        | src/uni-v3-staker/UniswapV3Staker.sol:UniswapV3Staker contract |                 |        |        |        |         |
        |----------------------------------------------------------------|-----------------|--------|--------|--------|---------|
        | Deployment Cost                                                | Deployment Size |        |        |        |         |
        | 4557691                                                        | 23359           |        |        |        |         |
        | Function Name                                                  | min             | avg    | median | max    | # calls |
        | createIncentive                                                | 54228           | 54228  | 54228  | 54228  | 1       |
        | deposits                                                       | 698             | 698    | 698    | 698    | 1       |
        | onERC721Received                                               | 235867          | 235867 | 235867 | 235867 | 1       |
        | updateGauges                                                   | 97735           | 97735  | 97735  | 97735  | 1       |
        */
        INonfungiblePositionManager _nonfungiblePositionManager = nonfungiblePositionManager;
        if (msg.sender != address(_nonfungiblePositionManager)) revert TokenNotUniswapV3NFT();

        /* @audit-followup Here they are using nonfungiblePositionManager directly */
        (IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);

        deposits[tokenId] = Deposit({owner: from, tickLower: tickLower, tickUpper: tickUpper, stakedTimestamp: 0});
        /* @audit Why is this event emitted before the _stakeToken? */
        emit DepositTransferred(tokenId, address(0), from);

        // stake the token in the current incentive
        _stakeToken(tokenId, pool, tickLower, tickUpper, liquidity);

        emit log("---------- UniswapV3Staker.onERC721Received callback ended ----------");
        return this.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAW TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok This function should not let withdraw someone elses token */
    /* @audit-ok Does this make sure that the recipient is aware of the ERC721? */
    /// @inheritdoc IUniswapV3Staker
    function withdrawToken(uint256 tokenId, address to, bytes memory data) external {
        if (to == address(0)) revert InvalidRecipient();

        Deposit storage deposit = deposits[tokenId];

        if (deposit.owner != msg.sender) revert NotCalledByOwner();
        if (deposit.stakedTimestamp != 0) revert TokenStakedError();

        delete deposits[tokenId];
        emit DepositTransferred(tokenId, msg.sender, address(0));

        nonfungiblePositionManager.safeTransferFrom(address(this), to, tokenId, data);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok What action writes to the rewards state variable? 
    * The _unstake function triggers rewards calculation and updates. */
    /// @inheritdoc IUniswapV3Staker
    function claimReward(address to, uint256 amountRequested) external returns (uint256 reward) {
        reward = rewards[msg.sender];
        if (amountRequested != 0 && amountRequested < reward) {
            reward = amountRequested;
            rewards[msg.sender] -= reward;
        } else {
            rewards[msg.sender] = 0;
        }

        if (reward > 0) hermes.safeTransfer(to, reward);

        emit RewardClaimed(to, reward);
    }

    /* @audit Does claiming the rewards require first unstaking? 
    * Yes it does require unstaking first (at least that's what they are doing in the tests). */
    /// @inheritdoc IUniswapV3Staker
    function claimAllRewards(address to) external returns (uint256 reward) {
        emit log("");
        emit log("==== UniswapV3Staker.claimAllRewards ====");

        emit log_named_address("[INFO] Msg.sender for rewards[msg.sender]: ", msg.sender);
        reward = rewards[msg.sender];

        emit log_named_uint("[INFO] User rewards: ", reward);

        rewards[msg.sender] = 0;

        emit log_named_uint("[INFO] User's hermes balance before: ", hermes.balanceOf(to));
        if (reward > 0) hermes.safeTransfer(to, reward);
        emit log_named_uint("[INFO] User's hermes balance after: ", hermes.balanceOf(to));

        emit RewardClaimed(to, reward);
        emit log("----------------------------------------");
    }

    /// @inheritdoc IUniswapV3Staker
    function getRewardInfo(IncentiveKey memory key, uint256 tokenId)
        external
        /* AUDIT view */
        override
        returns (uint256 reward, uint160 secondsInsideX128)
    {
        emit log("");
        emit log("==== UniswapV3Staker.getRewardInfo ====");
        Deposit storage deposit = deposits[tokenId];

        (uint96 endTime, uint256 stakedDuration) =
            IncentiveTime.getEndAndDuration(key.startTime, deposit.stakedTimestamp, block.timestamp);

        emit log_named_uint("[INFO] Incentive start time: ", key.startTime);
        emit log_named_uint("[INFO] Deposit staked timestamp: ", deposit.stakedTimestamp);
        emit log_named_uint("[INFO] Current block timestamp: ", block.timestamp);
        emit log("Calculation: IncentiveTime.getEndAndDuration()");
        emit log_named_uint("[CALC] Incentive end time: ", endTime);
        emit log_named_uint("[CALC] Deposit duration: ", stakedDuration);

        bytes32 incentiveId = IncentiveId.compute(key);
        emit log_named_bytes32("[INFO] Computed incentiveId: ", incentiveId);

        {
            uint128 boostAmount;
            uint128 boostTotalSupply;
            address owner = deposit.owner;
            // If tokenId is attached to gauge
            if (_userAttachements[owner][key.pool] == tokenId) {
                // get boost amount and total supply
                (boostAmount, boostTotalSupply) = hermesGaugeBoost.getUserGaugeBoost(owner, address(gauges[key.pool]));
            }

            emit log_named_uint("[INFO] User attachements [owner][key.pool]: ", _userAttachements[owner][key.pool]);
            emit log_named_address("[INFO] Deposit owner: ", owner);
            emit log_named_uint("[INFO] User boost amount: ", boostAmount);
            emit log_named_uint("[INFO] Boost total supply: ", boostTotalSupply);

            (uint160 secondsPerLiquidityInsideInitialX128, uint128 liquidity) = stakes(tokenId, incentiveId);
            if (liquidity == 0) revert TokenNotStaked();

            (, uint160 secondsPerLiquidityInsideX128,) =
                key.pool.snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);

            secondsInsideX128 = RewardMath.computeBoostedSecondsInsideX128(
                stakedDuration,
                liquidity,
                uint128(boostAmount),
                uint128(boostTotalSupply),
                secondsPerLiquidityInsideInitialX128,
                secondsPerLiquidityInsideX128
            );
        }

        Incentive storage incentive = incentives[incentiveId];
        reward = RewardMath.computeBoostedRewardAmount(
            incentive.totalRewardUnclaimed,
            incentive.totalSecondsClaimedX128,
            key.startTime,
            endTime,
            secondsInsideX128,
            block.timestamp
        );
        emit log("----------------------------------------");
    }

    /*//////////////////////////////////////////////////////////////
                            RE-STAKE TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function restakeToken(uint256 tokenId) external {
        emit log("");
        emit log("==== UniswapV3Staker.restakeToken ====");
        IncentiveKey storage incentiveId = stakedIncentiveKey[tokenId];
        /* @audit-confirmed Shouldn't the flag isNotRestake be false here? 
        * This flag should be false, so that anyone can restake. See testRestake_AnyoneCanRestakeAfterIncentiveEnds test 
        * 
        * To remove the overhead rename the flag to isRestake and change the logic in _unstake accordingly. */
        console.log("[INFO] incentiveId.startTime: %s != 0 -> %s", incentiveId.startTime, incentiveId.startTime != 0);
        if (incentiveId.startTime != 0) _unstakeToken(incentiveId, tokenId, true);

        (IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);

        _stakeToken(tokenId, pool, tickLower, tickUpper, liquidity);
        emit log("----- UniswapV3Staker.restakeToken completed ------");
    }

    /*//////////////////////////////////////////////////////////////
                            UNSTAKE TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Staker
    function unstakeToken(uint256 tokenId) external {
        IncentiveKey storage incentiveId = stakedIncentiveKey[tokenId];
        /* @audit-ok What is this check about? It's all over the code. 
        * The incentive program has to be started */
        if (incentiveId.startTime != 0) _unstakeToken(incentiveId, tokenId, true);
    }

    /// @inheritdoc IUniswapV3Staker
    function unstakeToken(IncentiveKey memory key, uint256 tokenId) external {
        _unstakeToken(key, tokenId, true);
    }

    /* @audit This function has many interactions. What are the things it does? */
    function _unstakeToken(IncentiveKey memory key, uint256 tokenId, bool isNotRestake) private {
        emit log("");
        emit log("==== UniswapV3Staker._unstakeToken ====");

        /* @info Liquidity NFT position info: owner, tick lower upper and when staked */
        Deposit storage deposit = deposits[tokenId];

        (uint96 endTime, uint256 stakedDuration) =
            IncentiveTime.getEndAndDuration(key.startTime, deposit.stakedTimestamp, block.timestamp);

        emit log_named_uint("[INFO] Incentive start time: ", key.startTime);
        emit log_named_uint("[INFO] Deposit staked timestamp: ", deposit.stakedTimestamp);
        emit log_named_uint("[INFO] Current block timestamp: ", block.timestamp);
        emit log_named_uint("[CALC] Incentive end time: ", endTime);
        emit log_named_uint("[CALC] Deposit duration: ", stakedDuration);

        address owner = deposit.owner;

        /* @audit-confirmed Is it really possible for anyone to restake? The isNotRestake is always hardcoded as true.
         * Remember that for this PoC it is necessary to add restakeToken to the interface as it is missing. 
         *
         * See function restakeToken as issue reference 
         */
        /* @audit-ok Is this check correct? Timestamp < endTime 
        * Yes, it is correct. NotOwner should not restake before the end time. */
        /* @audit Check default value of isNotRestake && does isNotRestake is true when is not restaken? */
        // anyone can call restakeToken if the block time is after the end time of the incentive
        console.log("isNotRestake: ", isNotRestake);
        console.log("block.timestamp < endTime: %s ", block.timestamp < endTime);
        console.log("owner != msg.sender: %s ", owner != msg.sender);
        if ((isNotRestake || block.timestamp < endTime) && owner != msg.sender) revert NotCalledByOwner();

        {
            // scope for bribeAddress, avoids stack too deep errors
            address bribeAddress = bribeDepots[key.pool];

        /* @audit What happens to the fees after they get to the depot? */
            if (bribeAddress != address(0)) {
                nonfungiblePositionManager.collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: tokenId,
                        recipient: bribeAddress,
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    })
                );
            }
        }

        bytes32 incentiveId = IncentiveId.compute(key);
        emit log_named_bytes32("[CALC] Incentive ID: ", incentiveId);
        uint160 secondsInsideX128;
        uint128 liquidity;
        {
            uint128 boostAmount;
            uint128 boostTotalSupply;

            UniswapV3Gauge gauge = gauges[key.pool]; // saves another SLOAD if no tokenId is attached

            // If tokenId is attached to gauge
            if (hermesGaugeBoost.isUserGauge(owner, address(gauge)) && _userAttachements[owner][key.pool] == tokenId) {
                emit log("[STATUS] User is attached to the gauge (`if` entered)");
                // get boost amount and total supply
                (boostAmount, boostTotalSupply) = hermesGaugeBoost.getUserGaugeBoost(owner, address(gauge));

                emit log_named_uint("[INFO] User boost amount: ", boostAmount);
                emit log_named_uint("[INFO] Boost total supply: ", boostTotalSupply);

                gauge.detachUser(owner);
                _userAttachements[owner][key.pool] = 0;
            }

            uint160 secondsPerLiquidityInsideInitialX128;
            (secondsPerLiquidityInsideInitialX128, liquidity) = stakes(tokenId, incentiveId);

            emit log_named_uint("[INFO] Seconds per liquidity inside INITIAL X128: ", secondsPerLiquidityInsideInitialX128);
            emit log_named_uint("[INFO] Liquidity: ", liquidity);

            if (liquidity == 0) revert TokenNotStaked();

            (, uint160 secondsPerLiquidityInsideX128,) =
                key.pool.snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);

            emit log_named_uint("[CALC] Seconds per liquidity inside X128: ", secondsPerLiquidityInsideX128);

            emit log("");
            emit log("Computing boosted seconds inside...");
            emit log("uint160 secondsInsideX128 = (secondsPerLiquidityInsideX128 - secondsPerLiquidityInsideInitialX128) * liquidity; ");
            emit log("If no boost -> 40% of that //// If boost -> 40% + 60%");
            emit log("");
        
            secondsInsideX128 = RewardMath.computeBoostedSecondsInsideX128(
                stakedDuration,
                liquidity,
                uint128(boostAmount),
                uint128(boostTotalSupply),
                secondsPerLiquidityInsideInitialX128,
                secondsPerLiquidityInsideX128
            );

            emit log_named_uint("[CALC] Boosted Seconds Inside: ", secondsInsideX128);
        }

        deposit.stakedTimestamp = 0;
        Incentive storage incentive = incentives[incentiveId];
        incentive.numberOfStakes--;
        uint256 reward = RewardMath.computeBoostedRewardAmount(
            incentive.totalRewardUnclaimed,
            incentive.totalSecondsClaimedX128,
            key.startTime,
            endTime,
            secondsInsideX128,
            block.timestamp
        );

        emit log_named_uint("[INFO] Total reward unclaimed: ", incentive.totalRewardUnclaimed);
        emit log_named_uint("[CALC] Boosted Reward Amount: ", reward);
        emit log_named_decimal_uint("[INFO] User Reward as a percentage of total unclaimed: ", reward * 100e18 / incentive.totalRewardUnclaimed, 18);

        unchecked {
            // if this overflows, e.g. after 2^32-1 full liquidity seconds have been claimed,
            // reward rate will fall drastically so it's safe
            // can't overflow if incentiveDuration < 2^32-1 seconds
            incentive.totalSecondsClaimedX128 += secondsInsideX128;
            // reward is never greater than total reward unclaimed
            incentive.totalRewardUnclaimed -= reward;
            // this only overflows if a token has a total supply greater than type(uint256).max
            rewards[owner] += reward;

            // this only overflows if a token has a total supply greater than type(uint256).max
            // Accounting purposes for external contracts only
            tokenIdRewards[tokenId] += reward;
        }

        Stake storage stake = _stakes[tokenId][incentiveId];
        stake.secondsPerLiquidityInsideInitialX128 = 0;
        stake.liquidityNoOverflow = 0;
        if (liquidity >= type(uint96).max) stake.liquidityIfOverflow = 0;
        delete stakedIncentiveKey[tokenId];
        emit TokenUnstaked(tokenId, incentiveId);
        emit log("----------------------------------------");
    }

    /*//////////////////////////////////////////////////////////////
                            STAKE TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Staker
    function stakeToken(uint256 tokenId) external override {
        if (deposits[tokenId].stakedTimestamp != 0) revert TokenStakedError();

        (IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            NFTPositionInfo.getPositionInfo(factory, nonfungiblePositionManager, tokenId);

        /* @audit Hardocded value for tests to skip init code hash */
        pool = IUniswapV3Pool(0xF0428617433652c9dc6D1093A42AdFbF30D29f74);

        _stakeToken(tokenId, pool, tickLower, tickUpper, liquidity);
    }

    /// @dev Stakes a deposited token without doing an already staked in another position check
    function _stakeToken(uint256 tokenId, IUniswapV3Pool pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        private
    {
        emit log("");
        emit log("==== UniswapV3Staker._stakeToken ====");
        emit log_named_uint("[INFO] Current timestamp: ", block.timestamp);
        emit log_named_uint("[INFO] Computed start time: ", IncentiveTime.computeStart(block.timestamp));
        emit log_named_address("[INFO] Pool: ", address(pool));
        IncentiveKey memory key = IncentiveKey({pool: pool, startTime: IncentiveTime.computeStart(block.timestamp)});

        bytes32 incentiveId = IncentiveId.compute(key);
        
        emit log_named_bytes32("[INFO] Computed incentiveId: ", incentiveId);
        emit log_named_uint("[INFO] Total rewards unclaimed: [incentiveId]: ", incentives[incentiveId].totalRewardUnclaimed);

        if (incentives[incentiveId].totalRewardUnclaimed == 0) revert NonExistentIncentiveError();

        if (uint24(tickUpper - tickLower) < poolsMinimumWidth[pool]) revert RangeTooSmallError();
        if (liquidity == 0) revert NoLiquidityError();

        stakedIncentiveKey[tokenId] = key;

        // If user not attached to gauge, attach
        address tokenOwner = deposits[tokenId].owner;
        if (tokenOwner == address(0)) revert TokenNotDeposited();

        UniswapV3Gauge gauge = gauges[pool]; // saves another SLOAD if no tokenId is attached

        /* @audit So if user sends the UNIv3NFT he gets attached to a gauge and receives the rewards. 
        * What does the gauge get from it? 
        * From my current understanding the protocol,
        * gets the bribes (fees from Uniswap) via MultiRewardsDepot contract */
        if (!hermesGaugeBoost.isUserGauge(tokenOwner, address(gauge))) {
            _userAttachements[tokenOwner][pool] = tokenId;
            gauge.attachUser(tokenOwner);
        }

        deposits[tokenId].stakedTimestamp = uint40(block.timestamp);
        incentives[incentiveId].numberOfStakes++;

        (, uint160 secondsPerLiquidityInsideX128,) = pool.snapshotCumulativesInside(tickLower, tickUpper);

        emit log_named_uint("[INFO] Seconds per liquidity inside X128: ", secondsPerLiquidityInsideX128);

        if (liquidity >= type(uint96).max) {
            _stakes[tokenId][incentiveId] = Stake({
                secondsPerLiquidityInsideInitialX128: secondsPerLiquidityInsideX128,
                liquidityNoOverflow: type(uint96).max,
                liquidityIfOverflow: liquidity
            });
        } else {
            Stake storage stake = _stakes[tokenId][incentiveId];
            stake.secondsPerLiquidityInsideInitialX128 = secondsPerLiquidityInsideX128;
            stake.liquidityNoOverflow = uint96(liquidity);
        }

        emit TokenStaked(tokenId, incentiveId, liquidity);
        emit log("----------------------------------------");
    }

    /*//////////////////////////////////////////////////////////////
                        GAUGE UPDATE LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok Why is this not access control protected? */
    /// @inheritdoc IUniswapV3Staker
    function updateGauges(IUniswapV3Pool uniswapV3Pool) external {
        /* @audit-ok Why is the address of univ3Pool passed as strategyGauges? 
        * The pool is a strategy */
        address uniswapV3Gauge = address(uniswapV3GaugeFactory.strategyGauges(address(uniswapV3Pool)));

        if (uniswapV3Gauge == address(0)) revert InvalidGauge();

        if (address(gauges[uniswapV3Pool]) != uniswapV3Gauge) {
            emit GaugeUpdated(uniswapV3Pool, uniswapV3Gauge);

            gauges[uniswapV3Pool] = UniswapV3Gauge(uniswapV3Gauge);
            gaugePool[uniswapV3Gauge] = uniswapV3Pool;
        }

        updateBribeDepot(uniswapV3Pool);
        updatePoolMinimumWidth(uniswapV3Pool);
    }

    /* @audit Why is this not access control protected? */
    /* @audit What are the bribes and bribeDepots? This must be connected to the way 
    * Hermes makes money. */
    /// @inheritdoc IUniswapV3Staker
    function updateBribeDepot(IUniswapV3Pool uniswapV3Pool) public {
        /* @info This is just returning the address of the depot that was deployed during gauge deployment. */ 
        /* @audit Is it possible to change the depot after deployment? 
        * It might be possible via FlywheelBribeRewards contract `setRewardsDepot()` */
        address newDepot = address(gauges[uniswapV3Pool].multiRewardsDepot());
        /* @audit-ok How is the initial value of bribeDepots set? 
        * The factory calls the updateGauges() which calls updateBribeDepot (this function),
        * the addr of the deployed depot is assigned to bribeDepots. */
        if (newDepot != bribeDepots[uniswapV3Pool]) {
            bribeDepots[uniswapV3Pool] = newDepot;

            emit BribeDepotUpdated(uniswapV3Pool, newDepot);
        }
    }

    /// @inheritdoc IUniswapV3Staker
    function updatePoolMinimumWidth(IUniswapV3Pool uniswapV3Pool) public {
        uint24 minimumWidth = gauges[uniswapV3Pool].minimumWidth();
        if (minimumWidth != poolsMinimumWidth[uniswapV3Pool]) {
            poolsMinimumWidth[uniswapV3Pool] = minimumWidth;

            emit PoolMinimumWidthUpdated(uniswapV3Pool, minimumWidth);
        }
    }
}
