// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IUniswapV3Staker} from "@v3-staker/interfaces/IUniswapV3Staker.sol";

import {BaseV2Gauge, FlywheelGaugeRewards} from "./BaseV2Gauge.sol";
import {IUniswapV3Gauge} from "./interfaces/IUniswapV3Gauge.sol";

/// @title Uniswap V3 Gauge - Handles liquidity provider incentives for Uniswap V3 in the Base V2 Gauge implementation.
contract UniswapV3Gauge is BaseV2Gauge, IUniswapV3Gauge {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                         GAUGE STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Gauge
    address public immutable override uniswapV3Staker;

    /// @inheritdoc IUniswapV3Gauge
    uint24 public override minimumWidth;

    /* @audit-ok Why are they passing pool address as the strategy address?
    * Isn't the staker contract a strategy? this might be an issue.
    *
    * A strategy is a Pool. There will be many pools (since there are many pairs). 
    * Each pool needs a gauge. There will be only one Staker, which acts as a manager. */
    /**
     * @notice Constructs the UniswapV3Gauge contract.
     * @param _flywheelGaugeRewards The FlywheelGaugeRewards contract.
     * @param _uniswapV3Staker The UniswapV3Staker contract.
     * @param _uniswapV3Pool The UniswapV3Pool contract.
     * @param _minimumWidth The minimum width.
     * @param _owner The owner of the contract.
     */
    constructor(
        FlywheelGaugeRewards _flywheelGaugeRewards,
        address _uniswapV3Staker,
        address _uniswapV3Pool,
        uint24 _minimumWidth,
        address _owner
    ) BaseV2Gauge(_flywheelGaugeRewards, _uniswapV3Pool, _owner) {
        uniswapV3Staker = _uniswapV3Staker;
        minimumWidth = _minimumWidth;

        emit NewMinimumWidth(_minimumWidth);

        rewardToken.safeApprove(_uniswapV3Staker, type(uint256).max);
    }

    /* @audit This is called whenever newEpoch() is called on the BaseV2Gauge.
    * Who is supposed to call newEpoch()? */
    /**
     *  @notice Distributes weekly emissions to the Uniswap V3 Staker for the current epoch.
     *  @dev must be called during the 12-hour offset after an epoch ends
     *       or rewards will be queued for the next epoch.
     */
    function distribute(uint256 amount) internal override {
        IUniswapV3Staker(uniswapV3Staker).createIncentiveFromGauge(amount);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUniswapV3Gauge
    function setMinimumWidth(uint24 _minimumWidth) external onlyOwner {
        minimumWidth = _minimumWidth;

        emit NewMinimumWidth(_minimumWidth);
    }

    /*//////////////////////////////////////////////////////////////
                         MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Only the UniswapV3Staker contract can attach and detach users.
    modifier onlyStrategy() override {
        if (msg.sender != uniswapV3Staker) revert StrategyError();
        _;
    }
}
