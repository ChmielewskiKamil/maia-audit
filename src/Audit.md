
### Hermes
 148 src/hermes/UtilityManager.sol ✅
 174 src/hermes/bHermes.sol ✅
 126 src/hermes/interfaces/IBaseV2Minter.sol ✅
 105 src/hermes/interfaces/IUtilityManager.sol ✅
  55 src/hermes/interfaces/IbHermesUnderlying.sol ✅
 168 src/hermes/minters/BaseV2Minter.sol ✅
  65 src/hermes/tokens/HERMES.sol ✅
  36 src/hermes/tokens/bHermesBoost.sol ✅
  43 src/hermes/tokens/bHermesGauges.sol ✅
  43 src/hermes/tokens/bHermesVotes.sol
 963 total

### ERC-4626
 174 src/erc-4626/ERC4626.sol
 130 src/erc-4626/ERC4626DepositOnly.sol ✅ // Experiment in local env how the VAULT works // 1 more time go through it
 295 src/erc-4626/ERC4626MultiToken.sol
 136 src/erc-4626/UlyssesERC4626.sol
  98 src/erc-4626/interfaces/IERC4626.sol
  69 src/erc-4626/interfaces/IERC4626DepositOnly.sol
 185 src/erc-4626/interfaces/IERC4626MultiToken.sol
  91 src/erc-4626/interfaces/IUlyssesERC4626.sol
1178 total

### ERC-20
 345 src/erc-20/ERC20Boost.sol ✅
 556 src/erc-20/ERC20Gauges.sol ✅
 379 src/erc-20/ERC20MultiVotes.sol
  10 src/erc-20/interfaces/Errors.sol
 239 src/erc-20/interfaces/IERC20Boost.sol ✅
 281 src/erc-20/interfaces/IERC20Gauges.sol ✅
 177 src/erc-20/interfaces/IERC20MultiVotes.sol
1987 total

### Gauges
 159 src/gauges/BaseV2Gauge.sol
  77 src/gauges/UniswapV3Gauge.sol
 166 src/gauges/factories/BaseV2GaugeFactory.sol
 164 src/gauges/factories/BaseV2GaugeManager.sol
 111 src/gauges/factories/BribesFactory.sol
 103 src/gauges/factories/UniswapV3GaugeFactory.sol
 143 src/gauges/interfaces/IBaseV2Gauge.sol
 131 src/gauges/interfaces/IBaseV2GaugeFactory.sol
 134 src/gauges/interfaces/IBaseV2GaugeManager.sol
  70 src/gauges/interfaces/IBribesFactory.sol
  77 src/gauges/interfaces/IUniswapV3Gauge.sol
  61 src/gauges/interfaces/IUniswapV3GaugeFactory.sol
1396 total

### Rewards
  43 src/rewards/FlywheelCoreInstant.sol
  42 src/rewards/FlywheelCoreStrategy.sol
  47 src/rewards/base/BaseFlywheelRewards.sol
 212 src/rewards/base/FlywheelCore.sol
  63 src/rewards/booster/FlywheelBoosterGaugeWeight.sol
  76 src/rewards/depots/MultiRewardsDepot.sol
  25 src/rewards/depots/RewardsDepot.sol
  44 src/rewards/depots/SingleRewardsDepot.sol
  43 src/rewards/interfaces/IFlywheelAcummulatedRewards.sol
  36 src/rewards/interfaces/IFlywheelBooster.sol
  40 src/rewards/interfaces/IFlywheelBribeRewards.sol
 147 src/rewards/interfaces/IFlywheelCore.sol
 107 src/rewards/interfaces/IFlywheelGaugeRewards.sol
  20 src/rewards/interfaces/IFlywheelInstantRewards.sol
  46 src/rewards/interfaces/IFlywheelRewards.sol
 103 src/rewards/interfaces/IMultiRewardsDepot.sol
  59 src/rewards/interfaces/IRewardsDepot.sol
  61 src/rewards/rewards/FlywheelAcummulatedRewards.sol
  43 src/rewards/rewards/FlywheelBribeRewards.sol
 236 src/rewards/rewards/FlywheelGaugeRewards.sol
  36 src/rewards/rewards/FlywheelInstantRewards.sol
1529 total

### Governance
 543 src/governance/GovernorBravoDelegateMaia.sol
  84 src/governance/GovernorBravoDelegator.sol
 206 src/governance/GovernorBravoInterfaces.sol
 833 total

### Maia
 169 src/maia/PartnerUtilityManager.sol
  96 src/maia/factories/PartnerManagerFactory.sol
  33 src/maia/interfaces/IBaseVault.sol
 112 src/maia/interfaces/IERC4626PartnerManager.sol
  84 src/maia/interfaces/IPartnerManagerFactory.sol
  45 src/maia/interfaces/IPartnerUtilityManager.sol
  62 src/maia/libraries/DateTimeLib.sol
 336 src/maia/tokens/ERC4626PartnerManager.sol
  58 src/maia/tokens/Maia.sol
 122 src/maia/vMaia.sol
1117 total

### Talos
 128 src/talos/TalosManager.sol
  91 src/talos/TalosOptimizer.sol
 181 src/talos/TalosStrategyStaked.sol
 171 src/talos/TalosStrategyVanilla.sol
 434 src/talos/base/TalosBaseStrategy.sol
 194 src/talos/boost-aggregator/BoostAggregator.sol
  58 src/talos/factories/BoostAggregatorFactory.sol
  56 src/talos/factories/OptimizerFactory.sol
  78 src/talos/factories/TalosBaseStrategyFactory.sol
  78 src/talos/factories/TalosStrategyStakedFactory.sol
  41 src/talos/factories/TalosStrategyVanillaFactory.sol
  41 src/talos/interfaces/AutomationCompatibleInterface.sol
 134 src/talos/interfaces/IBoostAggregator.sol
  61 src/talos/interfaces/IBoostAggregatorFactory.sol
  46 src/talos/interfaces/IOptimizerFactory.sol
 272 src/talos/interfaces/ITalosBaseStrategy.sol
  73 src/talos/interfaces/ITalosBaseStrategyFactory.sol
  35 src/talos/interfaces/ITalosManager.sol
  76 src/talos/interfaces/ITalosOptimizer.sol
  36 src/talos/interfaces/ITalosStrategyStaked.sol
  39 src/talos/interfaces/ITalosStrategyStakedFactory.sol
 104 src/talos/libraries/PoolActions.sol
 262 src/talos/libraries/PoolVariables.sol
  47 src/talos/strategies/TalosStrategySimple.sol
2736 total

### Ulysses AMM
1222 src/ulysses-amm/UlyssesPool.sol
  96 src/ulysses-amm/UlyssesRouter.sol
 122 src/ulysses-amm/UlyssesToken.sol
 166 src/ulysses-amm/factories/UlyssesFactory.sol
  73 src/ulysses-amm/interfaces/IUlyssesFactory.sol
 238 src/ulysses-amm/interfaces/IUlyssesPool.sol
 106 src/ulysses-amm/interfaces/IUlyssesRouter.sol
  76 src/ulysses-amm/interfaces/IUlyssesToken.sol
2099 total

### Ulysses Omnichain
 203 src/ulysses-omnichain/ArbitrumBranchBridgeAgent.sol
 155 src/ulysses-omnichain/ArbitrumBranchPort.sol
 158 src/ulysses-omnichain/ArbitrumCoreBranchRouter.sol
 152 src/ulysses-omnichain/BaseBranchRouter.sol
1420 src/ulysses-omnichain/BranchBridgeAgent.sol
 158 src/ulysses-omnichain/BranchBridgeAgentExecutor.sol
 429 src/ulysses-omnichain/BranchPort.sol
 288 src/ulysses-omnichain/CoreBranchRouter.sol
 471 src/ulysses-omnichain/CoreRootRouter.sol
 511 src/ulysses-omnichain/MulticallRootRouter.sol
1335 src/ulysses-omnichain/RootBridgeAgent.sol
 428 src/ulysses-omnichain/RootBridgeAgentExecutor.sol
 532 src/ulysses-omnichain/RootPort.sol
  75 src/ulysses-omnichain/VirtualAccount.sol
 106 src/ulysses-omnichain/factories/ArbitrumBranchBridgeAgentFactory.sol
 141 src/ulysses-omnichain/factories/BranchBridgeAgentFactory.sol
  85 src/ulysses-omnichain/factories/ERC20hTokenBranchFactory.sol
  80 src/ulysses-omnichain/factories/ERC20hTokenRootFactory.sol
  90 src/ulysses-omnichain/factories/RootBridgeAgentFactory.sol
  14 src/ulysses-omnichain/interfaces/IAnycallConfig.sol
  18 src/ulysses-omnichain/interfaces/IAnycallExecutor.sol
  22 src/ulysses-omnichain/interfaces/IAnycallProxy.sol
  22 src/ulysses-omnichain/interfaces/IApp.sol
  47 src/ulysses-omnichain/interfaces/IArbitrumBranchPort.sol
 401 src/ulysses-omnichain/interfaces/IBranchBridgeAgent.sol
  22 src/ulysses-omnichain/interfaces/IBranchBridgeAgentFactory.sol
 224 src/ulysses-omnichain/interfaces/IBranchPort.sol
 126 src/ulysses-omnichain/interfaces/IBranchRouter.sol
  56 src/ulysses-omnichain/interfaces/ICoreBranchRouter.sol
  29 src/ulysses-omnichain/interfaces/IERC20hTokenBranch.sol
  31 src/ulysses-omnichain/interfaces/IERC20hTokenBranchFactory.sol
  62 src/ulysses-omnichain/interfaces/IERC20hTokenRoot.sol
  29 src/ulysses-omnichain/interfaces/IERC20hTokenRootFactory.sol
  21 src/ulysses-omnichain/interfaces/IMulticall2.sol
  30 src/ulysses-omnichain/interfaces/IPortStrategy.sol
 413 src/ulysses-omnichain/interfaces/IRootBridgeAgent.sol
  17 src/ulysses-omnichain/interfaces/IRootBridgeAgentFactory.sol
 346 src/ulysses-omnichain/interfaces/IRootPort.sol
 122 src/ulysses-omnichain/interfaces/IRootRouter.sol
  57 src/ulysses-omnichain/interfaces/IVirtualAccount.sol
  12 src/ulysses-omnichain/interfaces/IWETH9.sol
  17 src/ulysses-omnichain/lib/AnycallFlags.sol
  32 src/ulysses-omnichain/token/ERC20hTokenBranch.sol
  88 src/ulysses-omnichain/token/ERC20hTokenRoot.sol
9075 total

### Uni V3 Staker
 561 src/uni-v3-staker/UniswapV3Staker.sol
 337 src/uni-v3-staker/interfaces/IUniswapV3Staker.sol
  19 src/uni-v3-staker/libraries/IncentiveId.sol
  48 src/uni-v3-staker/libraries/IncentiveTime.sol
  38 src/uni-v3-staker/libraries/NFTPositionInfo.sol
  71 src/uni-v3-staker/libraries/RewardMath.sol
1074 total

