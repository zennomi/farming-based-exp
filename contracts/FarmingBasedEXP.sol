// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {DistributionManagerNFTs} from "./DistributionManagerNFTs.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {NFT721Test} from "./NFT721Test.sol";

contract FarmingBasedEXP is
    OwnableUpgradeable,
    DistributionManagerNFTs,
    IERC721ReceiverUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*
    ╔══════════════════════════════╗
    
    ║           VARIABLES          ║
    
    ╚══════════════════════════════╝
    */

    struct NFTInfo {
        address owner;
        uint256 exp;
        uint128 level;
        uint128 depositTime;
    }

    mapping(uint256 => NFTInfo) public nftInfos;
    // user => level => amount
    mapping(address => mapping(uint256 => uint256)) public balances;
    mapping(uint128 => uint256) public totalValues;

    address receiveVault;
    address rewardsVault;
    IERC20Upgradeable rewardToken;
    NFT721Test nftContract;

    /*
    ╔══════════════════════════════╗
    
    ║            EVENTS            ║
    
    ╚══════════════════════════════╝
    */

    event Stake(address indexed user, uint256[] nftId, uint128 level);

    event RedeemAndClaim(
        address indexed user,
        uint256 indexed nftId,
        uint256 indexed rarity,
        uint256 amount
    );

    /*
    ╔══════════════════════════════╗
    
    ║         CONSTRUCTOR          ║
    
    ╚══════════════════════════════╝
    */

    function initialize(
        uint256 _distributionDuration,
        NFT721Test _nftContract,
        IERC20Upgradeable _rewardToken,
        address _receiveVault,
        address _rewardsVault
    ) external initializer {
        require(
            address(_nftContract) != address(0),
            "INVALID ADDRESS: _nftContract"
        );
        require(
            address(_rewardToken) != address(0),
            "INVALID ADDRESS: _rewardToken"
        );
        require(_receiveVault != address(0), "INVALID ADDRESS: _receiveVault");
        require(_rewardsVault != address(0), "INVALID ADDRESS: _rewardsVault");
        __Ownable_init();
        nftContract = _nftContract;
        rewardToken = _rewardToken;
        receiveVault = _receiveVault;
        rewardsVault = _rewardsVault;
        distributionEnd = block.timestamp + _distributionDuration;
    }

    /*
    ╔══════════════════════════════╗
    
    ║       ADMIN FUNCTIONS        ║

    ╚══════════════════════════════╝
    */

    function setRewardToken(IERC20Upgradeable _rewardToken) external onlyOwner {
        require(address(_rewardToken) != address(0), "INVALID ADDRESS");
        rewardToken = _rewardToken;
    }

    function increaseDistribution(uint256 distributionDuration)
        external
        onlyOwner
    {
        distributionEnd = distributionEnd + distributionDuration;
    }

    function setReceiveVault(address _receiveVault) external onlyOwner {
        require(_receiveVault != address(0), "INVALID ADDRESS");
        receiveVault = _receiveVault;
    }

    function setRewardsVault(address _rewardsVault) external onlyOwner {
        require(address(_rewardsVault) != address(0), "INVALID ADDRESS");
        rewardsVault = _rewardsVault;
    }

    function configureAsset(
        uint128[] calldata _rarity,
        uint128[] calldata _inputEmissionPerSecond
    ) external onlyOwner {
        require(
            _rarity.length == _inputEmissionPerSecond.length,
            "Do not have the same length"
        );

        PoolConfigInput[] memory poolConfigInputs = new PoolConfigInput[](
            _rarity.length
        );

        for (uint256 i; i < _rarity.length; i++) {
            poolConfigInputs[i].poolNumber = _rarity[i];
            poolConfigInputs[i].emissionPerSecond = _inputEmissionPerSecond[i];
            poolConfigInputs[i].totalValue = totalValues[_rarity[i]];
        }
        _configurePools(poolConfigInputs);
    }

    function transferAllRewardToken(address _receiver) external onlyOwner {
        rewardToken.safeTransfer(
            _receiver,
            IERC20Upgradeable(rewardToken).balanceOf(address(this))
        );
    }

    /*
    ╔══════════════════════════════╗
    
    ║       EXTERNAL FUNCTIONS     ║
    
    ╚══════════════════════════════╝
  */

    // Stake many nft in one level
    function stake(uint256[] calldata _ids, uint128 _level) external {
        require(msg.sender == tx.origin, "Not a wallet!");

        uint256 sumExp;
        uint256 totalValue = totalValues[_level];

        for (uint256 i; i < _ids.length; i++) {
            uint256 id = _ids[i];
            nftContract.transferFrom(msg.sender, address(this), id);

            uint128 rarityOfToken = uint128(
                nftContract.viewCollectionRarity(id)
            );
            require(
                rarityOfToken >= _level,
                "The rarity of the nft doesn't fit"
            );

            uint256 expOfToken = nftContract.getCollectionExperience(id);
            sumExp += expOfToken;
            
            NFTInfo memory nftInfo = NFTInfo({
                owner: msg.sender,
                exp: expOfToken,
                level: _level,
                depositTime: uint128(block.timestamp)
            });

            nftInfos[id] = nftInfo;

            _updateNFTPoolInternal(id, _level, 0, totalValue);
        }

        balances[msg.sender][_level] += _ids.length;
        totalValues[_level] += sumExp;

        emit Stake(msg.sender, _ids, _level);
    }

    function redeemAndClaim(uint256[] calldata _ids, uint128 _level) external {
        require(msg.sender == tx.origin, "Not a wallet!");

        uint256 totalReward;
        uint256 totalValue = totalValues[_level];

        for(uint256 i; i< _ids.length; i++){
            uint256 id = _ids[i];
            NFTInfo memory nftInfo = nftInfos[id];
            delete nftInfos[id];
 
            address owner = nftInfo.owner;
            require(msg.sender == owner, "You do not own this NFT");

            uint128 level = nftInfo.level;
            require(level == _level, "Redeem the wrong vault");

            uint256 exp = nftInfo.exp; 
            totalReward += _updateNFTPoolInternal(id, level, exp, totalValue);
            totalValue -= exp;

            // Transfer back NFT
            nftContract.transferFrom(address(this), msg.sender, id);
        }

        // Transfer reward token
        rewardToken.safeTransferFrom(rewardsVault, msg.sender, totalReward);

        balances[msg.sender][_level] -= _ids.length;

        totalValues[_level] = totalValue;
    }

    function getTotalRewardsBalance(uint256[] calldata _ids)
        external
        view
        returns (uint256)
    {   
        uint256 totalReward;
        for(uint256 i; i < _ids.length; i++){
            uint256 id = _ids[i];
            NFTInfo memory nftInfo = nftInfos[id];
            uint128 level = nftInfo.level;
            NFTStakeInput memory nftStakeInput = NFTStakeInput({
                poolNumber: level,
                NFTVaule: nftInfo.exp,
                totalValue: totalValues[level]
            });

            totalReward += _getUnclaimedRewards(id, nftStakeInput);
        }

        return totalReward;
    }

    function getStakingNFTinALevel(address _user, uint128 _level)
        external
        view
        returns (uint256[] memory)
    {}

    /*
  ╔══════════════════════════════╗
  
  ║       INTERNAL FUNCTIONS     ║
  
  ╚══════════════════════════════╝
  */

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
        return 0x150b7a02;
    }
}
