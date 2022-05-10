pragma solidity ^0.8.0;

contract DistributionManagerNFTs  {
  
  struct PoolData {
    uint128 emissionPerSecond;
    uint128 lastUpdateTimestamp;
    uint256 index;
    mapping(uint256 => uint256) nfts;
  }

  struct PoolConfigInput {
    uint128 poolNumber;
    uint128 emissionPerSecond;
    uint256 totalValue;
  }

  struct NFTStakeInput {
    uint128 poolNumber;
    uint256 NFTVaule;
    uint256 totalValue;
  }

  uint256 public distributionEnd;

  uint8 public constant PRECISION = 18;

  mapping(uint128 => PoolData) public pools;

  event PoolConfigUpdated(uint128 indexed poolNumber, uint256 emission);
  event PoolIndexUpdated(uint128 indexed poolNumber, uint256 index);
  event NFTIndexUpdated(uint256 indexed nft, uint128 indexed poolNumber, uint256 index);

  /**
   * @dev Configures the distribution of rewards for a list of pools
   * @param poolsConfigInput The list of configurations to apply
   **/
  function _configurePools(PoolConfigInput[] memory poolsConfigInput)
    internal
  {

    for (uint256 i = 0; i < poolsConfigInput.length; i++) {
      PoolData storage poolConfig = pools[poolsConfigInput[i].poolNumber];

      _updatePoolStateInternal(
        poolsConfigInput[i].poolNumber,
        poolConfig,
        poolsConfigInput[i].totalValue
      );

      poolConfig.emissionPerSecond = poolsConfigInput[i].emissionPerSecond;

      emit PoolConfigUpdated(
        poolsConfigInput[i].poolNumber,
        poolsConfigInput[i].emissionPerSecond
      );
    }
  }

  /**
   * @dev Updates the state of one distribution, mainly rewards index and timestamp
   * @param poolNumber The number of the pool
   * @param poolConfig Storage pointer to the distribution's config
   * @param totalValue Current total of value in this pool
   * @return The new distribution index
   **/
  function _updatePoolStateInternal(
    uint128 poolNumber,
    PoolData storage poolConfig,
    uint256 totalValue
  ) internal returns (uint256) {
    uint256 oldIndex = poolConfig.index;
    uint128 lastUpdateTimestamp = poolConfig.lastUpdateTimestamp;

    if (block.timestamp == lastUpdateTimestamp) {
      return oldIndex;
    }

    uint256 newIndex =
      _getPoolIndex(oldIndex, poolConfig.emissionPerSecond, lastUpdateTimestamp, totalValue);

    if (newIndex != oldIndex) {
      poolConfig.index = newIndex;
      emit PoolIndexUpdated(poolNumber, newIndex);
    }

    poolConfig.lastUpdateTimestamp = uint128(block.timestamp);

    return newIndex;
  }

  /**
   * @dev Updates the state of an nft in a distribution
   * @param nft The nft's id
   * @param poolNumber The number of the pool
   * @param NFTVaule Value of the NFT
   * @param totalValue Total value
   * @return The accrued rewards for the nft until the moment
   **/
  function _updateNFTPoolInternal(
    uint256 nft,
    uint128 poolNumber,
    uint256 NFTVaule,
    uint256 totalValue
  ) internal returns (uint256) {
    PoolData storage poolData = pools[poolNumber];
    uint256 nftIndex = poolData.nfts[nft];
    uint256 accruedRewards = 0;

    uint256 newIndex = _updatePoolStateInternal(poolNumber, poolData, totalValue);

    if (nftIndex != newIndex) {
      if (NFTVaule != 0) {
        accruedRewards = _getRewards(NFTVaule, newIndex, nftIndex);
      }

      poolData.nfts[nft] = newIndex;
      emit NFTIndexUpdated(nft, poolNumber, newIndex);
    }

    return accruedRewards;
  }

  /**
   * @dev Return the accrued rewards for an nft
   * @param nft The id of the nft
   * @param stake Struct of the nft data
   * @return The accrued rewards for the nft until the moment
   **/
  function _getUnclaimedRewards(uint256 nft, NFTStakeInput memory stake)
    internal
    view
    returns (uint256)
  {
    uint256 accruedRewards = 0;

    PoolData storage poolConfig = pools[stake.poolNumber];
    uint256 poolIndex =
      _getPoolIndex(
        poolConfig.index,
        poolConfig.emissionPerSecond,
        poolConfig.lastUpdateTimestamp,
        stake.totalValue
      );

    accruedRewards = accruedRewards + (
      _getRewards(stake.NFTVaule, poolIndex, poolConfig.nfts[nft])
    );

    return accruedRewards;
  }

  /**
   * @dev Internal function for the calculation of nft's rewards on a distribution
   * @param principalNFTBalance Value of the nft on a distribution
   * @param reserveIndex Current index of the distribution
   * @param userIndex Index stored for the nft, representation nft staking moment
   * @return The rewards
   **/
  function _getRewards(
    uint256 principalNFTBalance,
    uint256 reserveIndex,
    uint256 userIndex
  ) internal pure returns (uint256) {
    return principalNFTBalance * (reserveIndex - userIndex) / (10**uint256(PRECISION));
  }

  /**
   * @dev Calculates the next value of an specific distribution index, with validations
   * @param currentIndex Current index of the distribution
   * @param emissionPerSecond Representing the total rewards distributed per second per pool unit, on the distribution
   * @param lastUpdateTimestamp Last moment this distribution was updated
   * @param totalBalance of tokens considered for the distribution
   * @return The new index.
   **/
  function _getPoolIndex(
    uint256 currentIndex,
    uint256 emissionPerSecond,
    uint128 lastUpdateTimestamp,
    uint256 totalBalance
  ) internal view returns (uint256) {
    if (
      emissionPerSecond == 0 ||
      totalBalance == 0 ||
      lastUpdateTimestamp == block.timestamp ||
      lastUpdateTimestamp >= distributionEnd
    ) {
      return currentIndex;
    }

    uint256 currentTimestamp =
      block.timestamp > distributionEnd ? distributionEnd : block.timestamp;
    uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;
    return
      emissionPerSecond * timeDelta * 10**uint256(PRECISION) / totalBalance + currentIndex;
  }

  /**
   * @dev Returns the data of an nft on a distribution
   * @param nft Address of the nft
   * @param poolNumber The number of the pool
   * @return The new index
   **/
  function getNFTPoolData(uint256 nft, uint128 poolNumber) public view returns (uint256) {
    return pools[poolNumber].nfts[nft];
  }
}
