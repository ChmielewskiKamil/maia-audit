// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {EnumerableSet} from "@lib/EnumerableSet.sol";

import {IBaseV2Gauge} from "@gauges/interfaces/IBaseV2Gauge.sol";

import {Errors} from "./interfaces/Errors.sol";
import {IERC20Boost} from "./interfaces/IERC20Boost.sol";

/// @title An ERC20 with an embedded attachment mechanism to keep track of boost
///        allocations to gauges.
abstract contract ERC20Boost is ERC20, Ownable, IERC20Boost {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCastLib for *;

    /*///////////////////////////////////////////////////////////////
                            GAUGE STATE
    //////////////////////////////////////////////////////////////*/

    /* @info User => Gauge => GaugeState */
    /// @inheritdoc IERC20Boost
    mapping(address => mapping(address => GaugeState)) public override getUserGaugeBoost;

    /// @inheritdoc IERC20Boost
    mapping(address => uint256) public override getUserBoost;

    /* @audit TODO This is a complex data structure deleting elements does not work
    * check https://github.com/sherlock-audit/2023-03-teller-judging/issues/88 
    * MAIA uses older version without the warning 
    * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/structs/EnumerableSet.sol*/
    mapping(address => EnumerableSet.AddressSet) internal _userGauges;

    /* @audit How to write to this? */
    EnumerableSet.AddressSet internal _gauges;

    // Store deprecated gauges in case a user needs to free dead boost
    EnumerableSet.AddressSet internal _deprecatedGauges;

    /*///////////////////////////////////////////////////////////////
                            VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20Boost
    function gauges() external view returns (address[] memory) {
        return _gauges.values();
    }

    /// @inheritdoc IERC20Boost
    function gauges(uint256 offset, uint256 num) external view returns (address[] memory values) {
        values = new address[](num);
        for (uint256 i = 0; i < num;) {
            unchecked {
                values[i] = _gauges.at(offset + i); // will revert if out of bounds
                i++;
            }
        }
    }

    /* @audit Is the 0 addr gauge a valid gauge? */
    /// @inheritdoc IERC20Boost
    function isGauge(address gauge) external view returns (bool) {
        return _gauges.contains(gauge) && !_deprecatedGauges.contains(gauge);
    }

    /// @inheritdoc IERC20Boost
    function numGauges() external view returns (uint256) {
        return _gauges.length();
    }

    /// @inheritdoc IERC20Boost
    function deprecatedGauges() external view returns (address[] memory) {
        return _deprecatedGauges.values();
    }

    /// @inheritdoc IERC20Boost
    function numDeprecatedGauges() external view returns (uint256) {
        return _deprecatedGauges.length();
    }

    /* @audit This is the remaining Hermes tokens or bHermes tokens? 
    * Hypothesis: It's bHermes?
    * I think its actually ERC20Boost tokens */
    /// @inheritdoc IERC20Boost
    function freeGaugeBoost(address user) public view returns (uint256) {
        return balanceOf[user] - getUserBoost[user];
    }

    /// @inheritdoc IERC20Boost
    function userGauges(address user) external view returns (address[] memory) {
        return _userGauges[user].values();
    }

    /// @inheritdoc IERC20Boost
    function isUserGauge(address user, address gauge) external view returns (bool) {
        return _userGauges[user].contains(gauge);
    }

    /// @inheritdoc IERC20Boost
    function userGauges(address user, uint256 offset, uint256 num) external view returns (address[] memory values) {
        values = new address[](num);
        for (uint256 i = 0; i < num;) {
            unchecked {
                values[i] = _userGauges[user].at(offset + i); // will revert if out of bounds
                i++;
            }
        }
    }

    /// @inheritdoc IERC20Boost
    function numUserGauges(address user) external view returns (uint256) {
        return _userGauges[user].length();
    }

    /*///////////////////////////////////////////////////////////////
                        GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /* @audit This is supposed to be only callable by the gauge, how is that enforced?
    * Only the admin can add a new gauge via `addGauge` function */
    /// @inheritdoc IERC20Boost
    function attach(address user) external {
        /* @audit-ok Is access control sufficient? 
        * 1: will revert if the sender is not active gauge 
        * 2: will revert if the sender is deprecated gauge
        */
        if (!_gauges.contains(msg.sender) || _deprecatedGauges.contains(msg.sender)) {
            revert InvalidGauge();
        }

        /* @audit What does idempotent mean? 
        * It means that no matter how many times we perform an operation, 
        * the result will always be the same. 
        * 
        * What does it mean in this context tho? */
        
        /* @audit I need to investigate how the enumerable set works.
        * What does the add function return? 

        Set.add function returns true if two conditions are met:
        * - the element was added to the set 
        * - the element was not present in the set before */

        /* @audit-ok What does this achieve? It maps the user to the sender?
        * The msg.sender is the gauge, this line adds the calling gauge to user gauges */
        // idempotent add
        if (!_userGauges[user].add(msg.sender)) revert GaugeAlreadyAttached();

        /* @audit-ok Why is it casting the uint256 balanceOf to uint128? 
        * They are casting it to uint128 because it will be later stored with the 
        * uint128 totalSupply in one struct. This will save space as two variables will be packed
        * in one slot. */
        uint128 userGaugeBoost = balanceOf[user].toUint128();

        /* @audit-ok This is comparing the uint256 to uint128, how does that work?
        * 
        * This case will only be dangerous if uint256 getUserBoost > uint128.max - THATS NOT CORRECt
        * This is safe as tested */
        /* @audit Given that this is called during staking the liquidity token, 
        * what if the user does not have the bHermes yet? 
        * 
        * getUserBoost will be 0, userGaugeBoost will also be 0, this won't be hit
        *
        * It's okay, the next lines will simply attach 0 to userGaugeBoost in the gaugeState,
        * User will earn HERMES the normal way and then he will boost his gauge. */
        if (getUserBoost[user] < userGaugeBoost) {
            getUserBoost[user] = userGaugeBoost;
            emit UpdateUserBoost(user, userGaugeBoost);
        }

        /* @audit-ok I don't understand it. Is it assigning the same thing as above the second time?
        * This is assigning to a different variable getUserBoost != getUserGaugeBoost
        * The getUserGaugeBoost returns the allocation for the specific gauge, while getUserBoost 
        * returns the allocation for all gauges. 
        * This function efectively attaches all of the user available boost to a gauge */
        /* @info Given that user had 0 bHermesBoost during the call, his userGaugeBoost will be 0 */
        getUserGaugeBoost[user][msg.sender] =
            GaugeState({userGaugeBoost: userGaugeBoost, totalGaugeBoost: totalSupply.toUint128()});

        emit Attach(user, msg.sender, userGaugeBoost);
    }

    /* @audit-ok Is access control sufficient?
    * The require will only pass after successful removal */
    /// @inheritdoc IERC20Boost
    function detach(address user) external {
        require(_userGauges[user].remove(msg.sender));
        /* @audit-ok Does this delete the element correctly? 
        * Yes, when deleting individual elements this works as expected */
        delete getUserGaugeBoost[user][msg.sender];

        emit Detach(user, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                        USER GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /* @audit If user has many gauges attached this might be DOS'ed.
    * Can one add gauges for other users? */
    /// @inheritdoc IERC20Boost
    function updateUserBoost(address user) external {
        uint256 userBoost = 0;

        /* @audit This is a really expensive operation, is there a DOS vector?
        * It copies entire storage to memory */
        address[] memory gaugeList = _userGauges[user].values();

        uint256 length = gaugeList.length;
        for (uint256 i = 0; i < length;) {
            address gauge = gaugeList[i];

            if (!_deprecatedGauges.contains(gauge)) {
                uint256 gaugeBoost = getUserGaugeBoost[user][gauge].userGaugeBoost;

                if (userBoost < gaugeBoost) userBoost = gaugeBoost;
            }

            unchecked {
                i++;
            }
        }
        getUserBoost[user] = userBoost;

        emit UpdateUserBoost(user, userBoost);
    }

    /// @inheritdoc IERC20Boost
    function decrementGaugeBoost(address gauge, uint256 boost) public {
        GaugeState storage gaugeState = getUserGaugeBoost[msg.sender][gauge];
        /* @audit-confirmed This should probably handle also the deprecated gauges,
        * just like the functions below decrementGaugesBoostIndexed
        * if (deprecated.contains || boost >= gaugeState) 
        *
        * See the decrementGaugesBoostIndexed function for the issue reference 
        * They should function the same, so that users are not confused. */
        if (boost >= gaugeState.userGaugeBoost) {
            /* @audit-confirmed NON-CRIT Return value of remove is unchecked, event will be emitted nonetheless */
            _userGauges[msg.sender].remove(gauge);
            delete getUserGaugeBoost[msg.sender][gauge];

            emit Detach(msg.sender, gauge);
        } else {
            gaugeState.userGaugeBoost -= boost.toUint128();

            emit DecrementUserGaugeBoost(msg.sender, gauge, gaugeState.userGaugeBoost);
        }
    }

    /// @inheritdoc IERC20Boost
    function decrementGaugeAllBoost(address gauge) external {
        require(_userGauges[msg.sender].remove(gauge));
        delete getUserGaugeBoost[msg.sender][gauge];

        emit Detach(msg.sender, gauge);
    }

    /// @inheritdoc IERC20Boost
    function decrementAllGaugesBoost(uint256 boost) external {
        decrementGaugesBoostIndexed(boost, 0, _userGauges[msg.sender].length());
    }

    /// @inheritdoc IERC20Boost
    function decrementGaugesBoostIndexed(uint256 boost, uint256 offset, uint256 num) public {
        address[] memory gaugeList = _userGauges[msg.sender].values();

        uint256 length = gaugeList.length;
        for (uint256 i = 0; i < num && i < length;) {
            address gauge = gaugeList[offset + i];

            GaugeState storage gaugeState = getUserGaugeBoost[msg.sender][gauge];

            /* @audit-confirmed What's special about this function that they are checking for deprecated gauges here
            * In the decrementGaugeBoost it was not checked. 
            *
            * Either remove the deprecated gauges check here, or add it to the decrementGaugeBoost function, 
            * so that user experience is the same in both functions. The question is: Should the functionality to
            * decrement gauges remove the boost from the deprecated gauges in it's entirety 
            * or just the amount specified. */
            if (_deprecatedGauges.contains(gauge) || boost >= gaugeState.userGaugeBoost) {
                require(_userGauges[msg.sender].remove(gauge)); // Remove from set. Should never fail.
                delete getUserGaugeBoost[msg.sender][gauge];

                emit Detach(msg.sender, gauge);
            } else {
                gaugeState.userGaugeBoost -= boost.toUint128();

                emit DecrementUserGaugeBoost(msg.sender, gauge, gaugeState.userGaugeBoost);
            }

            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IERC20Boost
    function decrementAllGaugesAllBoost() external {
        // Loop through all user gauges, live and deprecated
        address[] memory gaugeList = _userGauges[msg.sender].values();

        // Free gauges until through the entire list
        uint256 size = gaugeList.length;
        for (uint256 i = 0; i < size;) {
            address gauge = gaugeList[i];

            require(_userGauges[msg.sender].remove(gauge)); // Remove from set. Should never fail.
            delete getUserGaugeBoost[msg.sender][gauge];

            emit Detach(msg.sender, gauge);

            unchecked {
                i++;
            }
        }

        /* @audit What is the diff between getUserBoost and getUserGaugeBoost */
        /* @audit-issue Shouldn't all of the functions update the getUserBoost at the end?
        * getUserBoost is used throughout this contract. And in the notAttached modifier which 
        * is used for transfers and burns.
        *
        * This refers to the security note in the IERC20 Boost 
        *
        * I think it's correct since the modifier is restrictive. The getUserBoost increases
        * only when the boost is attached to a gauge. The only way to decrease it is to remove all boost from all gauges */
        getUserBoost[msg.sender] = 0;

        emit UpdateUserBoost(msg.sender, 0);
    }

    /*///////////////////////////////////////////////////////////////
                        ADMIN GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20Boost
    function addGauge(address gauge) external onlyOwner {
        _addGauge(gauge);
    }

    function _addGauge(address gauge) internal {
        bool newAdd = _gauges.add(gauge);
        /* @info set.remove returns true when two conditions are met:
        * value was succesfuly removed
        * it was actually present in the set */
        bool previouslyDeprecated = _deprecatedGauges.remove(gauge);
        /* @audit newAdd will be true when:
        * - it was succesfuly added 
        * - it wasn't already present
        * previouslyDeprecated will be true when:
        * - it was succesfuly removed
        * - it was present
        * This means that the expression below will revert when:
        * - gauge was already present in gauges
        * - or gauge wasn't deprecated */
        
        // add and fail loud if zero address or already present and not deprecated
        if (gauge == address(0) || !(newAdd || previouslyDeprecated)) revert InvalidGauge();

        emit AddGauge(gauge);
    }

    /// @inheritdoc IERC20Boost
    function removeGauge(address gauge) external onlyOwner {
        _removeGauge(gauge);
    }

    function _removeGauge(address gauge) internal {
        /* @audit-confirmed Comment is incorrect:
        * it should fail loud if it is already deprecated 
        * add will return false when: 
            * gauge was already present in deprecated 
        * if will revert when this happens */
        // add to deprecated and fail loud if not present
        if (!_deprecatedGauges.add(gauge)) revert InvalidGauge();

        emit RemoveGauge(gauge);
    }

    /// @inheritdoc IERC20Boost
    function replaceGauge(address oldGauge, address newGauge) external onlyOwner {
        _removeGauge(oldGauge);
        _addGauge(newGauge);
    }

    /*///////////////////////////////////////////////////////////////
                             ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// NOTE: any "removal" of tokens from a user requires notAttached < amount.

    /**
     * @notice Burns `amount` of tokens from `from` address.
     * @dev User must have enough free boost.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function _burn(address from, uint256 amount) internal override notAttached(from, amount) {
        super._burn(from, amount);
    }

    /**
     * @notice Transfers `amount` of tokens from `msg.sender` to `to` address.
     * @dev User must have enough free boost.
     * @param to the address to transfer to.
     * @param amount the amount to transfer.
     */
    function transfer(address to, uint256 amount) public override notAttached(msg.sender, amount) returns (bool) {
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfers `amount` of tokens from `from` address to `to` address.
     * @dev User must have enough free boost.
     * @param from the address to transfer from.
     * @param to the address to transfer to.
     * @param amount the amount to transfer.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notAttached(from, amount)
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    /*///////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reverts if the user does not have enough free boost.
     * @param user The user address.
     * @param amount The amount of boost.
     */
    modifier notAttached(address user, uint256 amount) {
        if (freeGaugeBoost(user) < amount) revert AttachedBoost();
        _;
    }
}
