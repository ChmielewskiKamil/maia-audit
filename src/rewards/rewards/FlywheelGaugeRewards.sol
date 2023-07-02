// SPDX-License-Identifier: MIT
// Rewards logic inspired by Tribe DAO Contracts (flywheel-v2/src/rewards/FlywheelGaugeRewards.sol)
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC20Gauges} from "@ERC20/ERC20Gauges.sol";

import {IFlywheelGaugeRewards} from "../interfaces/IFlywheelGaugeRewards.sol";

import {IBaseV2Minter} from "@hermes/interfaces/IBaseV2Minter.sol";

/// @title Flywheel Gauge Reward Stream
contract FlywheelGaugeRewards is Ownable, IFlywheelGaugeRewards, Test {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////
                        REWARDS CONTRACT STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelGaugeRewards
    ERC20Gauges public immutable override gaugeToken;

    /// @notice the minter contract, is a rewardsStream to collect rewards from
    IBaseV2Minter public immutable minter;

    /// @inheritdoc IFlywheelGaugeRewards
    address public immutable override rewardToken;

    /* @audit-ok What writes to gaugeCycle? 
    * - Initial gaugeCycle is set in the constructor
    * - After that it is updated in the queueRewardsForCycle and queueRewardsForCyclePaginated functions 
    * to the currentCycle after calling minter.updatePeriod() */
    /// @inheritdoc IFlywheelGaugeRewards
    uint32 public override gaugeCycle;

    /// @inheritdoc IFlywheelGaugeRewards
    uint32 public immutable override gaugeCycleLength;

    /// @inheritdoc IFlywheelGaugeRewards
    mapping(ERC20 => QueuedRewards) public override gaugeQueuedRewards;

    /// @notice the start of the next cycle being partially queued
    uint32 internal nextCycle;

    // rewards that made it into a partial queue but didn't get completed
    uint112 internal nextCycleQueuedRewards;

    // the offset during pagination of the queue
    uint32 internal paginationOffset;

    constructor(address _rewardToken, address _owner, ERC20Gauges _gaugeToken, IBaseV2Minter _minter) {
        _initializeOwner(_owner);
        rewardToken = _rewardToken;

        gaugeCycleLength = _gaugeToken.gaugeCycleLength();

        // seed initial gaugeCycle
        /* @audit The same precision loss as in BaseV2Minter? */
        gaugeCycle = (block.timestamp.toUint32() / gaugeCycleLength) * gaugeCycleLength;

        gaugeToken = _gaugeToken;

        minter = _minter;
    }

    /*//////////////////////////////////////////////////////////////
                        GAUGE REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelGaugeRewards
    function queueRewardsForCycle() external returns (uint256 totalQueuedForCycle) {
        emit log("");
        emit log("==== FlywheelGaugeRewards.queueRewardsForCycle ====");

        /* @audit-reported Typo in the comment -> Not found by the bot. rewars -> rewards */
        /* @audit-ok Check if this is not a re-entrancy issue */
        /* @audit-ok updatePeriod returns uint256, why is the return value not checked 
        * Not an issue*/
        /// @dev Update minter cycle and queue rewars if needed.
        /// This will make this call fail if it is a new epoch, because the minter calls this function, the first call would fail with "CycleError()".
        /// Should be called through Minter to kickoff new epoch.
        console.log("[STATUS] Trying to call minter.updatePeriod()");
        minter.updatePeriod();
        emit log("Update period done");

        // next cycle is always the next even divisor of the cycle length above current block timestamp.
        uint32 currentCycle = (block.timestamp.toUint32() / gaugeCycleLength) * gaugeCycleLength;
        uint32 lastCycle = gaugeCycle;

        // ensure new cycle has begun
        console.log("currentCycle %s has to be > lastCycle %s -> %s", currentCycle, lastCycle, currentCycle > lastCycle);
        if (currentCycle <= lastCycle) revert CycleError();

        console.log("[STATUS] Setting gaugeCycle to currentCycle: %s", currentCycle);
        gaugeCycle = currentCycle;

        // queue the rewards stream and sanity check the tokens were received
        uint256 balanceBefore = rewardToken.balanceOf(address(this));

        /* @audit-ok Where is the transfer of HERMES to gauge? In the getAccruedRewards at the very bottom of the call */
        /* @info This call triggers the transfer of HERMES tokens from BaseV2Minter to this contract */
        /* @audit This transfers `weekly` which is the weekly emission */
        totalQueuedForCycle = minter.getRewards();
        emit log("Get rewards done");

        /* @audit-ok Isn't totalQueuedForCycle always 0 at this point? It wasn't modified before 
        * NO, it is modified above. GetRewards() returns newWeeklyEmission */
        require(rewardToken.balanceOf(address(this)) - balanceBefore >= totalQueuedForCycle);

        /* @audit-ok Shouldn't this line be moved above the require above? */
        /* @audit-ok What writes to nextCycleQueuedRewards? 
        * They are only set in the queueRewardsForCyclePaginated. 
        * They are set in a similar way as here:
        * newRewards = minter.getRewards(),
        * and nextCycleQueuedRewards += newRewards */
        // include uncompleted cycle
        totalQueuedForCycle += nextCycleQueuedRewards;

        // iterate over all gauges and update the rewards allocations
        /* @audit-ok What writes to gaugeToken.gauges? 
        * ERC20Gauges#AddGauge() and ERC20Gauges#ReplaceGauge() both onlyOwner protected. */
        address[] memory gauges = gaugeToken.gauges();

        emit log("Calling _queueRewards with: gauges, currentCycle, lastCycle, totalQueuedForCycle");
        emit log_named_uint("gauges: It is an array of length: ", gauges.length);
        emit log_named_uint("currentCycle: ", currentCycle);
        emit log_named_uint("lastCycle: ", lastCycle);
        emit log_named_uint("totalQueuedForCycle: ", totalQueuedForCycle);
        /* @audit-issue If you first call the paginated version, some of the gauges will already be queued. 
        * What is the implication of that? */
        _queueRewards(gauges, currentCycle, lastCycle, totalQueuedForCycle);

        nextCycleQueuedRewards = 0;
        paginationOffset = 0;

        emit CycleStart(currentCycle, totalQueuedForCycle);
        emit log("---- queueRewardsForCycle END ----");
    }

    /* @audit-issue Is there any situatin where a call to this function as a standalone call (not through minter) is 
    * supposed to succeed? */
    /* @audit-ok Whats the purpose of Paginated version? 
    * As opposed to the non paginated version, this function is not used anywhere in the code, just in the tests.
    * It's behaviour should be exactly the same as the other function. 
    *
    * This function will queue for rewards a number of gauges specified by the caller. For example there are 5 gauges 
    * left to be queued for rewards. You can call this function with numRewards = 2 and 2 gauges will be queued, 
    * the paginationOffset will be set to 2, and later when someone will try to queue the gauges,
    * it will start from the offset */
    /* @audit-issue Given the above explanation, make sure that no other function
    * queues the first 2 gauges the second time. */
    /// @inheritdoc IFlywheelGaugeRewards
    function queueRewardsForCyclePaginated(uint256 numRewards) external {
        /// @dev Update minter cycle and queue rewars if needed.
        /// This will make this call fail if it is a new epoch, because the minter calls this function, the first call would fail with "CycleError()".
        /// Should be called through Minter to kickoff new epoch.
        minter.updatePeriod();

        // next cycle is always the next even divisor of the cycle length above current block timestamp.
        uint32 currentCycle = (block.timestamp.toUint32() / gaugeCycleLength) * gaugeCycleLength;
        /* @audit-ok Where is gaugeCycle increased? 
        * It is assigned to currentCycle after the check currentCycle <= lastCycle passes */
        uint32 lastCycle = gaugeCycle;

        // ensure new cycle has begun
        console.log("currentCycle %s has to be > lastCycle %s -> %s", currentCycle, lastCycle, currentCycle > lastCycle);
        if (currentCycle <= lastCycle) revert CycleError();

        /* @audit-ok What writes to the nextCycle? 
        * This is the only place where nextCycle is written to */
        /* @audit-ok Where is nextCycle read? 
        * This is the only place where it is read. */
        /* @audit-ok Is it possible to have currentCycle > lastCycle && currentCycle < nextCycle? 
        * It is not possible to have currentCycle < nextCycle, because this is the only place where
        * nextCycle is written to and currentCycle will always be >= nextCycle */
        /* @audit-issue This is absent in the non-paginated version */
        /* @audit-issue Why is it writing to nextCycle instead of the gaugeCycle? */
        /* @audit The sole purpose of `nextCycle` is to reset paginationOffset. What is it used for? */
        if (currentCycle > nextCycle) {
            nextCycle = currentCycle;
            paginationOffset = 0;
        }

        /* @audit-issue What is offset used for? It is dependant on the nextCycle variable. */
        uint32 offset = paginationOffset;

        /* @audit This will only be hit on the first call in the cycle */
        // important to only calculate the reward amount once to prevent each page from having a different reward amount
        if (offset == 0) {
            // queue the rewards stream and sanity check the tokens were received
            uint256 balanceBefore = rewardToken.balanceOf(address(this));
            uint256 newRewards = minter.getRewards();
            require(rewardToken.balanceOf(address(this)) - balanceBefore >= newRewards);
            require(newRewards <= type(uint112).max); // safe cast
            nextCycleQueuedRewards += uint112(newRewards); // in case a previous incomplete cycle had rewards, add on
        }

        uint112 queued = nextCycleQueuedRewards;

        /* @audit-ok When the offset is non 0? 
        * The offset will be non 0 only if you are queueing the rewards in the same cycle (it's not a new cycle). */
        /* @audit-ok What writes to numGauges? 
        * The same thing that writes to _gauges, so only the addGauge function. NumGauges is just length of gauges set */
        uint256 remaining = gaugeToken.numGauges() - offset;

        /* @audit-ok What happens when I pass numRewards == 0? Answered inside function body. */
        // Important to do non-strict inequality to include the case where the numRewards is just enough to complete the cycle
        if (remaining <= numRewards) {
            /* @audit-ok Why is the input parameter overriden here? 
            * The purpose of that is to always queue as much gauges as user wants and no more, 
            * in the if block when remaining > numRewards they will return numRewards 
            * Here because remaining < numRewards we will queue remaining. */
            numRewards = remaining;
            /* @audit-issue Why is the gaugeCycle not updated in a case when remaining > numRewards? */
            console.log("[STATUS] Setting gaugeCycle to currentCycle: %s", currentCycle);
            gaugeCycle = currentCycle;
            nextCycleQueuedRewards = 0;
            paginationOffset = 0;
            emit CycleStart(currentCycle, queued);
        } else {
            /* @audit If I pass numRewards == 0, given that remaining != 0, the else block will be hit. After extending:
            * paginationOffset = paginationOffset + numRewards (zero) will be equal to paginationOffset 
            *
            * When remaining > numRewards the paginationOffset will be set to numRewards */
            paginationOffset = offset + numRewards.toUint32();
        }

        // iterate over all gauges and update the rewards allocations
        address[] memory gauges = gaugeToken.gauges(offset, numRewards);

        _queueRewards(gauges, currentCycle, lastCycle, queued);
        /* @audit This function differs from the one above: 
        * - It does not set nextCycleQueuedRewards to 0 after the _queueRewards.
        * It does that before. 
        * - It also uses queued instead of totalQueuedForCycle */
    }

    /*//////////////////////////////////////////////////////////////
                        FLYWHEEL CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /* @info This is the core function of this contract, it reads the gauge state for the previous cycle 
    * and determines how many reward tokens it will get in the current cycle. */
    /* @audit Is the next cycle the current cycle then?*/
    /**
     * @notice Queues the rewards for the next cycle for each given gauge.
     * @param gauges array of gauges addresses to queue rewards for.
     * @param currentCycle timestamp representing the beginning of the new cycle.
     * @param lastCycle timestamp representing the end of the of the last cycle.
     * @param totalQueuedForCycle total number of rewards queued for the next cycle.
     */
    function _queueRewards(address[] memory gauges, uint32 currentCycle, uint32 lastCycle, uint256 totalQueuedForCycle)
        internal
    {
        uint256 size = gauges.length;

        if (size == 0) revert EmptyGaugesError();

        for (uint256 i = 0; i < size; i++) {
            ERC20 gauge = ERC20(gauges[i]);

            QueuedRewards memory queuedRewards = gaugeQueuedRewards[gauge];

            console.log("Gauge storedCycle: %s has to be smaller than currentCycle: %s -> %s", queuedRewards.storedCycle, currentCycle, queuedRewards.storedCycle < currentCycle);
            /* @audit How do you start the cycle queue? The updatePeriod starts it? */
            // Cycle queue already started
            /* @audit-confirmed Add explicit revert string or a custom error. In a situation where gauge were queued
            * using the paginated function it's stored cycle has been updated. The following check will revert
            * with with EvmError: Revert 
            *
            * It is also not noted anywhere that queueRewardsForCycle will revert if
            * incomplete pagination was performed. 
            *
            * The string below has been added by me */
            require(queuedRewards.storedCycle < currentCycle, "Gauge was already queued");
            /* @audit-ok If this assertion could be broken, the rewards withdrawal would be bricked 
            * 
            * How is the storedCycle set?
            * storedCycle is set inside this function and nowhere else.
            * It is set to the currentCycle which is calculated in the queueRewardsForCycle and paginated functions 
            *
            * How is the lastCycle set? 
            * lastCycle is the gaugeCycle before update in queueRewardsForCycle and paginated functions 
            *
            * It seems that it is not possible to break this assertion because last cycle is dependant on the 
            * current cycle and current cycle (stored cycle) uses bigger timestamp */
            assert(queuedRewards.storedCycle == 0 || queuedRewards.storedCycle >= lastCycle);

            /* @audit Is this correct? What is the stored cycle? Should the last cycle be given cycleRewards? */
            uint112 completedRewards = queuedRewards.storedCycle == lastCycle ? queuedRewards.cycleRewards : 0;
            /* @info This line handles how much will be alocated to each gauge */
            uint256 nextRewards = gaugeToken.calculateGaugeAllocation(address(gauge), totalQueuedForCycle);
            require(nextRewards <= type(uint112).max); // safe cast

            gaugeQueuedRewards[gauge] = QueuedRewards({
                priorCycleRewards: queuedRewards.priorCycleRewards + completedRewards,
                cycleRewards: uint112(nextRewards),
                storedCycle: currentCycle
            });

            emit QueueRewards(address(gauge), currentCycle, nextRewards);
        }
    }

    /* @audit-ok Is Gauge supposed to call this function? YES */
    /* @audit-ok There seem to be no access control on this function 
    * The only way to follow this up would be if you could modify the gaugeQueuedRewards for arbitrary sender 
    * Not an issue because in order to write to the gaugeQueuedRewards[gauge] you need to control gauge list,
    * which is access controlled by the onlyOwner 
    * 
    * What writes to `gaugeQueuedRewards`? 
    * - This function writes to `gaugeQueuedRewards`
    * - The `_queueRewards` also writes to it 
    * how is the first assignment performed then?
    *
    * */
    /// @inheritdoc IFlywheelGaugeRewards
    function getAccruedRewards() external returns (uint256 accruedRewards) {
        emit log("");
        emit log("==== FlywheelGaugeRewards.getAccruedRewards ====");
        /// @dev Update minter cycle and queue rewars if needed.
        minter.updatePeriod();

        emit log_named_address("[INFO] gaugeQueuedRewards[ERC20(msg.sender)] -> msg.sender: ", msg.sender);
        QueuedRewards memory queuedRewards = gaugeQueuedRewards[ERC20(msg.sender)];

        uint32 cycle = gaugeCycle;
        /* @audit-followup If msg.sender would be some arbitrary contract, storedCycle would be 0,
        * meaning that `incompleteCycle` would be false */
        bool incompleteCycle = queuedRewards.storedCycle > cycle;
        emit log_named_uint("[INFO] Cycle: ", cycle);
        emit log_named_uint("[INFO] Stored Cycle: ", queuedRewards.storedCycle);
        console.log("[INFO] Is cycle complete? (incompleteCycle): ", incompleteCycle);

        emit log("[STATUS] if priorCycleRewards == 0 && (cycleRewards == 0 || incompleteCycle) accruedRewards = 0");
        emit log_named_uint("[INFO] Prior cycle rewards: ", queuedRewards.priorCycleRewards);
        emit log_named_uint("[INFO] Cycle rewards: ", queuedRewards.cycleRewards);
        /* @audit-followup 
        * - The 1st part would be true 
        * - The 2nd part would be true as well bcs cycleRewards would be 0 
        * Meaning it would return 0 for accrued rewards */
        // no rewards
        if (queuedRewards.priorCycleRewards == 0 && (queuedRewards.cycleRewards == 0 || incompleteCycle)) {
            return 0;
        }

        // if stored cycle != 0 it must be >= the last queued cycle
        assert(queuedRewards.storedCycle >= cycle);

        // always accrue prior rewards
        accruedRewards = queuedRewards.priorCycleRewards;
        uint112 cycleRewardsNext = queuedRewards.cycleRewards;

        if (incompleteCycle) {
            // If current cycle queue incomplete, do nothing to current cycle rewards or accrued
        } else {
            accruedRewards += cycleRewardsNext;
            cycleRewardsNext = 0;
        }

        gaugeQueuedRewards[ERC20(msg.sender)] = QueuedRewards({
            priorCycleRewards: 0,
            cycleRewards: cycleRewardsNext,
            /* @audit This is just assigning the same value? */
            storedCycle: queuedRewards.storedCycle
        });

        if (accruedRewards > 0) rewardToken.safeTransfer(msg.sender, accruedRewards);
        emit log("----- getAccruedRewards END -----");
    }
}
