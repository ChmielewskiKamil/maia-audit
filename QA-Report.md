# Maia DAO - QA Report

## Summary

| Risk | Title | File | Instances |
| :--: | --- | :---: | :---: |
| L-01 | `restakeToken` is not permissionless | [UniswapV3Staker.sol](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/uni-v3-staker/UniswapV3Staker.sol#L340-L348) | 1 | 
| L-0X | Incorrect NatSpec comment on `claimAllRewards` | [IUniswapV3Staker.sol](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol#L207) | 1 | 
| L-0X | The functionality of `decrementGaugeBoost` and `decrementGaugesBoostIndexed` differs |  | 1 | 
| N-0X | `userDelegatedVotes` does not belong to admin operations | [IERC20MultiVotes.sol](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/interfaces/IERC20MultiVotes.sol#L91) | 1 | 
| N-0X | The return value of `EnumerableSet.remove` is unchecked | [ERC20Boost.sol](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L178) | 1 | 
| Total | | --- | --- |

## [N-01] `userDelegatedVotes` does not belong to admin operations
*Code styling*

The `userDelegatedVotes` function is placed next to the admin operations in the `IERC20MultiVotes` interface. It is a view function that should be placed a couple of lines below, next to other "Delegation Logic" functions. 

[IERC20MultiVotes#userDelegatedVotes](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/interfaces/IERC20MultiVotes.sol#L91)

Fix: 
```diff
diff --git a/src/erc-20/interfaces/IERC20MultiVotes.sol b/src/erc-20/interfaces/IERC20MultiVotes.sol
index c628293..476c9aa 100644
--- a/src/erc-20/interfaces/IERC20MultiVotes.sol
+++ b/src/erc-20/interfaces/IERC20MultiVotes.sol
@@ -85,15 +85,15 @@ interface IERC20MultiVotes {
      */
     function setContractExceedMaxDelegates(address account, bool canExceedMax) external;
 
+    /*///////////////////////////////////////////////////////////////
+                        DELEGATION LOGIC
+    //////////////////////////////////////////////////////////////*/
+    
     /**
      * @notice mapping from a delegator to the total number of delegated votes.
      */
     function userDelegatedVotes(address) external view returns (uint256);
 
-    /*///////////////////////////////////////////////////////////////
-                        DELEGATION LOGIC
-    //////////////////////////////////////////////////////////////*/
-
     /**
      * @notice Get the amount of votes currently delegated by `delegator` to `delegatee`.
      * @param delegator the account which is delegating votes to `delegatee`.
```


## [N-0X] Incorrect NatSpec comment on `claimAllRewards`
The `@notice` comment on the [`IUniswapV3Staker#claimAllRewards`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol#L207) function is incorrect. It states that the `claimAllRewards` function transfers `amountRequested` to the recipient, while it transfers all of the rewards. 

It also benefits the users to add the information that the `unstakeToken` or `restakeToken` should be called before this function. Otherwise, the reward balance won't be updated. 

Fix:
```diff
diff --git a/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol b/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol
index 895c505..6b57bed 100644
--- a/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol
+++ b/src/uni-v3-staker/interfaces/IUniswapV3Staker.sol
@@ -204,7 +204,7 @@ interface IUniswapV3Staker is IERC721Receiver {
     /// @return reward The amount of reward tokens claimed
     function claimReward(address to, uint256 amountRequested) external returns (uint256 reward);
 
-    /// @notice Transfers `amountRequested` of accrued `rewardToken` rewards from the contract to the recipient `to`
+    /// @notice Transfers all of the accrued `rewardToken` rewards from the contract to the recipient `to`
     /// @param to The address where claimed rewards will be sent to
     /// @return reward The amount of reward tokens claimed
     function claimAllRewards(address to) external returns (uint256 reward);
```


## [N-0X] The return value of `EnumerableSet.remove` is unchecked
The `EnumerableSet.remove` function returns a status boolean on a successful removal. The [`ERC20Boost#decrementGaugeBoost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L178) function does not check for that value. Other similar functions like [`decrementGaugeAllBoost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L191C1-L191C1), [`decrementGaugesBoostIndexed`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L213) and [`decrementAllGaugesAllBoost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L239C13-L239C13) do check the return value. 

In a situation where incorrect gauge address were passed to the `decrementGaugeBoost` function, the `Detach` event would be emitted nonetheless. 

Fix:

```diff
diff --git a/src/erc-20/ERC20Boost.sol b/src/erc-20/ERC20Boost.sol
index a1da4df..f12fd2c 100644
--- a/src/erc-20/ERC20Boost.sol
+++ b/src/erc-20/ERC20Boost.sol
@@ -175,7 +175,7 @@ abstract contract ERC20Boost is ERC20, Ownable, IERC20Boost {
     function decrementGaugeBoost(address gauge, uint256 boost) public {
         GaugeState storage gaugeState = getUserGaugeBoost[msg.sender][gauge];
         if (boost >= gaugeState.userGaugeBoost) {
-            _userGauges[msg.sender].remove(gauge);
+            require(_userGauges[msg.sender].remove(gauge));
             delete getUserGaugeBoost[msg.sender][gauge];
 
             emit Detach(msg.sender, gauge);
```
## [L-0X] The functionality of `decrementGaugeBoost` and `decrementGaugesBoostIndexed` differs
According to the spec in the [`IERC20Boost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/interfaces/IERC20Boost.sol#L178) interface, the [`decrementGaugeBoost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L175-L187) and [`decrementGaugesBoostIndexed`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L203-L227) should function the same, with the latter being an indexed version of the former. 

It is not the case. The difference lies in the way they handle deprecated gauges. The `decrementGaugesBoostIndexed` function, when supplied with a deprecated gauge, will remove the user gauge boost entirely. The `decrementGaugeBoost` will either decrease the deprecated gauge's user boost or delete it, depending on whether the [`uint256 boost` is `>= gaugeState.userGaugeBoost`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L177C9-L177C48). 

This is happening because `decrementGaugesBoostIndexed` explicitly checks if [`_deprecatedGauges.contains(gauge)`](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L212) while `decrementGaugeBoost` [does not](https://github.com/code-423n4/2023-05-maia/blob/54a45beb1428d85999da3f721f923cbf36ee3d35/src/erc-20/ERC20Boost.sol#L177). 

It is up to the protocol team to decide whether the user gauge boost should be removed from deprecated gauges or just be decremented. 

Things to consider:
- Users expect consistent behaviour from similar functions.
- Since gauges can be reactivated, someone might not want to remove the boost from it.

If boost were to be removed:
```diff
diff --git a/src/erc-20/ERC20Boost.sol b/src/erc-20/ERC20Boost.sol
index a1da4df..9f13074 100644
--- a/src/erc-20/ERC20Boost.sol
+++ b/src/erc-20/ERC20Boost.sol
@@ -174,7 +174,7 @@ abstract contract ERC20Boost is ERC20, Ownable, IERC20Boost {
     /// @inheritdoc IERC20Boost
     function decrementGaugeBoost(address gauge, uint256 boost) public {
         GaugeState storage gaugeState = getUserGaugeBoost[msg.sender][gauge];
-        if (boost >= gaugeState.userGaugeBoost) {
+        if (_deprecatedGauges.contains(gauge) || boost >= gaugeState.userGaugeBoost) {
             _userGauges[msg.sender].remove(gauge);
             delete getUserGaugeBoost[msg.sender][gauge];
```

And if it were to be decremented:
```diff
diff --git a/src/erc-20/ERC20Boost.sol b/src/erc-20/ERC20Boost.sol
index a1da4df..51bad76 100644
--- a/src/erc-20/ERC20Boost.sol
+++ b/src/erc-20/ERC20Boost.sol
@@ -209,7 +209,7 @@ abstract contract ERC20Boost is ERC20, Ownable, IERC20Boost {
 
             GaugeState storage gaugeState = getUserGaugeBoost[msg.sender][gauge];
 
-            if (_deprecatedGauges.contains(gauge) || boost >= gaugeState.userGaugeBoost) {
+            if (boost >= gaugeState.userGaugeBoost) {
                 require(_userGauges[msg.sender].remove(gauge)); // Remove from set. Should never fail.
                 delete getUserGaugeBoost[msg.sender][gauge];
```
