// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IRewardsDepot} from "../interfaces/IRewardsDepot.sol";

/* @audit This is inherited by both the SingleRewardDepot and MultiRewardDepot 
* From my current understanding:
* - SingleRewardDepot is used for instant rewards 
* - MultiRewardDepot is used for strategy rewards */
/// @title Rewards Depot - Base contract for reward token storage
abstract contract RewardsDepot is IRewardsDepot {
    using SafeTransferLib for address;

    ///  @inheritdoc IRewardsDepot
    function getRewards() external virtual returns (uint256);

    /// @notice Transfer balance of token to rewards contract
    function transferRewards(address _asset, address _rewardsContract) internal returns (uint256 balance) {
        balance = _asset.balanceOf(address(this));
        /* @audit Where are the funds transferred? */
        _asset.safeTransfer(_rewardsContract, balance);
    }

    modifier onlyFlywheelRewards() virtual;
}
