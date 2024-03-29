// SPDX-License-Identifier: MIT
// Rewards logic inspired by Tribe DAO Contracts (flywheel-v2/src/rewards/FlywheelDynamicRewards.sol)
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {FlywheelCore} from "../base/FlywheelCore.sol";
import {RewardsDepot} from "../depots/RewardsDepot.sol";
import {FlywheelAcummulatedRewards} from "../rewards/FlywheelAcummulatedRewards.sol";

import {IFlywheelBribeRewards} from "../interfaces/IFlywheelBribeRewards.sol";

/// @title Flywheel Accumulated Bribes Reward Stream
contract FlywheelBribeRewards is FlywheelAcummulatedRewards, IFlywheelBribeRewards {
    /*//////////////////////////////////////////////////////////////
                        REWARDS CONTRACT STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFlywheelBribeRewards
    mapping(ERC20 => RewardsDepot) public override rewardsDepots;

    /**
     * @notice Flywheel Accumulated Bribes Reward Stream constructor.
     *  @param _flywheel flywheel core contract
     *  @param _rewardsCycleLength the length of a rewards cycle in seconds
     */
    constructor(FlywheelCore _flywheel, uint256 _rewardsCycleLength)
        FlywheelAcummulatedRewards(_flywheel, _rewardsCycleLength)
    {}

    /* @audit-ok This is the hook that was mentioned somwhere.
    * It is called as a result from FlywheelCore accrueStrategy() */
    /// @notice calculate and transfer accrued rewards to flywheel core
    function getNextCycleRewards(ERC20 strategy) internal override returns (uint256) {
        /* @audit As my comment from RewardsDepot: This is probably the MultiRewardsDepot */
        return rewardsDepots[strategy].getRewards();
    }

    /* @audit-ok Why does anyone can call this? 
    * This is probably okay because of the admin whitelisting mentioned below */
    /// @inheritdoc IFlywheelBribeRewards
    function setRewardsDepot(RewardsDepot rewardsDepot) external {
        /* @audit Where is this whitelisting happening?
        * The admin uses the addStrategyForRewards in FlywheelCore 
        * If you try to accrue the rewards before that, functions will return early with 0 */
        /// @dev Anyone can call this, whitelisting is handled in FlywheelCore
        rewardsDepots[ERC20(msg.sender)] = rewardsDepot;

        emit AddRewardsDepot(msg.sender, rewardsDepot);
    }
}
