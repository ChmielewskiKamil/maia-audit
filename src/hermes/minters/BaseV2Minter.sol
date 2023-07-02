// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC4626} from "@ERC4626/ERC4626.sol";

import {HERMES} from "@hermes/tokens/HERMES.sol";

import {FlywheelGaugeRewards} from "@rewards/rewards/FlywheelGaugeRewards.sol";

import {IBaseV2Minter} from "../interfaces/IBaseV2Minter.sol";

/* @info
* The reward stream in the gauges come from the BaseV2Minter, this contract is responsible for
* creating the HERMES reward token. */
/* @audit What is the B(3, 3) system? */
/// @title Base V2 Minter - Mints HERMES tokens for the B(3,3) system
contract BaseV2Minter is Ownable, IBaseV2Minter, Test {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                         MINTER STATE
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok 86400 seconds is 1 day */
    /// @dev allows minting once per week (reset every Thursday 00:00 UTC)
    uint256 internal constant week = 86400 * 7;
    /// @dev 2% per week target emission
    uint256 internal constant base = 1000;

    uint256 internal constant max_tail_emission = 100;
    uint256 internal constant max_dao_share = 300;

    /// @inheritdoc IBaseV2Minter
    address public immutable override underlying;
    /// @inheritdoc IBaseV2Minter
    ERC4626 public immutable override vault;

    /// @inheritdoc IBaseV2Minter
    FlywheelGaugeRewards public override flywheelGaugeRewards;
    /// @inheritdoc IBaseV2Minter
    address public override dao;

    /// @inheritdoc IBaseV2Minter
    uint256 public override daoShare = 100;
    uint256 public override tailEmission = 20;
    /// @inheritdoc IBaseV2Minter

    /// @inheritdoc IBaseV2Minter
    uint256 public override weekly;
    /// @inheritdoc IBaseV2Minter
    uint256 public override activePeriod;

    address internal initializer;

    constructor(
        address _vault, // the B(3,3) system that will be locked into
        address _dao,
        address _owner
    ) {
        _initializeOwner(_owner);
        initializer = msg.sender;
        dao = _dao;
        underlying = address(ERC4626(_vault).asset());
        vault = ERC4626(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                         FALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit What's the reason behind this fallback? */
    fallback() external {
        updatePeriod();
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok Can't be frontrun since initializer is set to deployer in constructor */
    // @audit-ok Callable only once since it renounces ownership
    /// @inheritdoc IBaseV2Minter
    function initialize(FlywheelGaugeRewards _flywheelGaugeRewards) external {
        if (initializer != msg.sender) revert NotInitializer();
        flywheelGaugeRewards = _flywheelGaugeRewards;
        initializer = address(0);
        /* @audit-ok Division before multiplication? Is this on purpose?
        * Due to the rounding down the activePeriod will be shifted by 5 days back from the current date.
        *
        * @TODO Investigate where this is used, is there comparison between the current 
        * block.timestamp and activePeriod? It will be shifted. 
        * - There is such comparison in the updatePeriod function, however it is not a problem there.
        * As tested in Test14 in sandbox */
        activePeriod = (block.timestamp / week) * week;
    }

    /// @inheritdoc IBaseV2Minter
    function setDao(address _dao) external onlyOwner {
        /// @dev DAO can be set to address(0) to disable DAO rewards.
        dao = _dao;
    }

    /* @audit-ok What if the dao share is set, but the dao address is set to addr(0)?
    * The share is set, but it won't be transferred because of 0 addr checks. */
    /// @inheritdoc IBaseV2Minter
    function setDaoShare(uint256 _daoShare) external onlyOwner {
        if (_daoShare > max_dao_share) revert DaoShareTooHigh();
        daoShare = _daoShare;
    }

    /// @inheritdoc IBaseV2Minter
    function setTailEmission(uint256 _tail_emission) external onlyOwner {
        if (_tail_emission > max_tail_emission) revert TailEmissionTooHigh();
        tailEmission = _tail_emission;
    }

    /*//////////////////////////////////////////////////////////////
                         EMISSION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseV2Minter
    function circulatingSupply() public  view  returns (uint256) {
        return HERMES(underlying).totalSupply() - vault.totalAssets();
    }

    /// @inheritdoc IBaseV2Minter
    function weeklyEmission() public /*view*/ returns (uint256) {
        emit log("");
        emit log("==== BaseV2Minter.weeklyEmission() ====");
        emit log_named_uint("[INFO] Circulating supply: ", circulatingSupply());
        emit log_named_uint("[INFO] Tail emission: ", tailEmission);
        emit log_named_uint("[INFO] Base: ", base);
        emit log_named_uint("[CALC] Calculated weekly emission: ", (circulatingSupply() * tailEmission) / base);
        emit log("---- weeklyEmission END ----");
        return (circulatingSupply() * tailEmission) / base;
    }

    /* @info _minted is the amount of minted bHermes */
    /// @inheritdoc IBaseV2Minter
    function calculateGrowth(uint256 _minted) public /*view*/ returns (uint256) {
        emit log("");
        emit log("==== BaseV2Minter.calculateGrowth() ====");
        emit log_named_uint("[INFO] Vault total assets: ", vault.totalAssets());
        emit log_named_uint("[INFO] Minted HERMES (newWeeklyEmission): ", _minted);
        emit log_named_uint("[INFO] HERMES total supply: ", HERMES(underlying).totalSupply());
        emit log_named_uint("[CALC] Calculated growth: ", (vault.totalAssets() * _minted) / HERMES(underlying).totalSupply());
        emit log("---- calculateGrowth END ----");
        return (vault.totalAssets() * _minted) / HERMES(underlying).totalSupply();
    }

    /* @audit-ok Is this function supposed to be permissionless? 
    * It will revert with unauthorized() because only Admin can mint new HERMES 
    * The admin (owner) of HERMES is the BaseV2Minter, he is the one calling here. */
    /// @inheritdoc IBaseV2Minter
    function updatePeriod() public returns (uint256) {
        emit log("");
        emit log("==== BaseV2Minter.updatePeriod() ====");
        /* @audit What writes to the activePeriod? 
        * The initialize() sets the initial period */
        uint256 _period = activePeriod;
        /* @audit-ok What happens if the protocol is not yet initialized 
        * Nothing happens */
        /* @audit Where is this function used */
        // only trigger if new week
        /* @audit-ok Because the activePeriod is shifted by 5 days, this can be updated 
        * faster than expected.
        * This is not an issue the shift is expected. No matter when you start the first period, it will be set to thurdsday 00:00
        * Every next period will follow this cycle. */
        if (block.timestamp >= _period + week && initializer == address(0)) {
            console.log("[INFO] Timestamp %s is greater than previous period %s + week %s", block.timestamp, _period, week);
            console.log("[INFO] Because of that, active period will be updated");
            /* @audit-ok The calculation below causes precision loss.
            * The calculated period + week will be equal to 4202150400 
            * When multiplied first and then divided the result is: 4202651988
            * The first unix time is: Thu Mar 01 2103 00:00:00 GMT+0000
            * The fixed version is: Tue Mar 06 2103 19:19:48 GMT+0000 
            *
            * This one will shift by another 5 days, but can be only called after 7 days.
            * The whole updating schedule will be shifted. After initialisation the update schedule
            * can be called 2 days sooner than expected. 
            *
            * THIS IS OK, I guess this is how it is supposed to work. */
            emit log_named_uint("[INFO] Current (previous) period: ", _period);
            _period = (block.timestamp / week) * week;
            emit log_named_uint("[CALC] New period: ", _period);

            activePeriod = _period;
            /* @audit For all the calculations below substitute the names with underlying 
            * calculations 
            *
            * 1. uint256 newWeeklyEmission = (circulatingSupply() * tailEmission) / base 
            *    uint256 newWeeklyEmission = ((HERMES(underlying).totalSupply() - vault.totalAssets()) * tailEmission) / base 
            *
            * 2. uint256 _growth = (vault.totalAssets() * _minted) / HERMES(underlying).totalSupply()
            *    uint256 _growth = 
            * (vault.totalAssets() * (((HERMES(underlying).totalSupply() - vault.totalAssets()) * tailEmission) / base)) / HERMES(underlying).totalSupply()*/
            uint256 newWeeklyEmission = weeklyEmission();
            /* @info This aggregates all of the weekly emissions */ 
            weekly += newWeeklyEmission;
            uint256 _circulatingSupply = circulatingSupply();

            uint256 _growth = calculateGrowth(newWeeklyEmission);
            uint256 _required = _growth + newWeeklyEmission;
            /* @audit Why are they multiplying the daoShare * required? */
            /// @dev share of newWeeklyEmission emissions sent to DAO.
            uint256 share = (_required * daoShare) / base;
            _required += share;
            uint256 _balanceOf = underlying.balanceOf(address(this));
            
            /* @info HERE IS THE MINT*/
            if (_balanceOf < _required) {
                emit log_named_address("[INFO] Address trying to mint: ", address(this));
                // emit log_named_address("[INFO] Hermes onlyOwner: ", address(HERMES(underlying).owner()));
                HERMES(underlying).mint(address(this), _required - _balanceOf);
                emit log("[STATUS] Succesful mint");
            }

            underlying.safeTransfer(address(vault), _growth);

            if (dao != address(0)) underlying.safeTransfer(dao, share);

            emit Mint(msg.sender, newWeeklyEmission, _circulatingSupply, _growth, share);

            /* @audit-ok Is it really the case that it won't enter? Possible re-entrancy. */
            /// @dev queue rewards for the cycle, anyone can call if fails
            ///      queueRewardsForCycle will call this function but won't enter
            ///      here because activePeriod was updated
            emit log("[STATUS] Trying to call flywheelGaugeRewards.queueRewardsForCycle()");
            try flywheelGaugeRewards.queueRewardsForCycle() { emit log("[SUCCESS] flywheelGaugeRewards.queueRewardsForCycle() succeeded");} catch {
                emit log("[ERROR] flywheelGaugeRewards.queueRewardsForCycle() failed");
            }
        }
        emit log("---- updatePeriod END ----");
        return _period;
    }

    /*//////////////////////////////////////////////////////////////
                         REWARDS STREAM LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-reported NON-CRITICAL Misleading function name, Getter performs transfer
    * Usually functions starting with get are getters (view functions) that read a variable. */
    /// @inheritdoc IBaseV2Minter
    function getRewards() external returns (uint256 totalQueuedForCycle) {
        if (address(flywheelGaugeRewards) != msg.sender) revert NotFlywheelGaugeRewards();
        totalQueuedForCycle = weekly;
        weekly = 0;
        underlying.safeTransfer(msg.sender, totalQueuedForCycle);
    }
}
