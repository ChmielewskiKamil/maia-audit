// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC4626DepositOnly} from "./interfaces/IERC4626DepositOnly.sol";

/* @audit QUESTIONS 
* - Is the amount of shares correctly calculated for the deposit amount? 
* - */

/// @title Minimal Deposit Only ERC4626 tokenized Vault implementation
/// @author Maia DAO (https://github.com/Maia-DAO)
abstract contract ERC4626DepositOnly is ERC20, IERC4626DepositOnly {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC20 public immutable asset;

    constructor(ERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol, _asset.decimals()) {
        asset = _asset;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok What's the difference between `deposit` and `mint`? 
    * In the `deposit` function user specifies the exact amount of assets that he wants to exchange to shares,
    * while in the `mint` function user specifies the exact amount of shares that he wants to receive */
    /// @inheritdoc IERC4626DepositOnly
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        address(asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /// @inheritdoc IERC4626DepositOnly
    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Need to transfer before minting or ERC777s could reenter.
        address(asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626DepositOnly
    function totalAssets() public view virtual returns (uint256);

    /// @inheritdoc IERC4626DepositOnly
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        /* @audit 
        * a - amount of assets to deposit 
        * B - Vault balance before the deposit (totalAssets)
        * T - Total shares before mint (totalSupply)
        * s - shares to mint 
        *
        * This function should calculates `s`
        *
        * According to smart contract programmer:
        * s = (a*T) / B 
        *
        * */
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDiv(supply, totalAssets());
    }
    
    /* @audit-ok Correct */
    /// TODO: @inheritdoc IERC4626DepositOnly
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDiv(totalAssets(), supply);
    }

    /// @inheritdoc IERC4626DepositOnly
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626DepositOnly
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626DepositOnly
    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @inheritdoc IERC4626DepositOnly
    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /* @audit-ok This function is not overriden anywhere and is used only in tests
    * THis might be the thing that is getting overriden in Talos */
    function afterDeposit(uint256 assets, uint256 shares) internal virtual {}
}
