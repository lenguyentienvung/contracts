// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract VoteCoin is Ownable, ReentrancyGuard {
    using Address for address payable;

    enum RewardType {
        Token,
        Ether
    }

    enum RoundItem {
        A,
        B
    }

    struct Round {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardsPerUser;
        RoundItemDescription itemA;
        RoundItemDescription itemB;
    }

    struct RoundItemDescription {
        string name;
        string logo;
        uint256 votesCount;
    }

    struct Vote {
        RoundItem item;
        uint256 earned;
        uint256 claimedAt;
        uint256 createdAt;
    }

    mapping(uint256 => Round) internal _rounds;
    mapping(uint256 => mapping(address => Vote)) internal _votes;

    uint256 internal _unclaimedTokens;
    uint256 internal _unclaimedEthers;

    uint256 public currentRoundId;
    RewardType public rewardType;

    IERC20Metadata public token;
    uint256 public minimumBalance;

    constructor(IERC20Metadata token_, RewardType rewardType_, uint256 miniumBalance_) {
        token = token_;
        rewardType = rewardType_;
        minimumBalance = miniumBalance_;
    }

    function vote(RoundItem item) external nonReentrant {
        require(isInVoteTime(currentRoundId), "not in vote time");
        require(!isVoted(currentRoundId, msg.sender), "already voted");
        require(isQualifiedToVote(msg.sender), "not enough token");

        _votes[currentRoundId][msg.sender] = Vote(item, 0, 0, block.timestamp);

        if (item == RoundItem.A) {
            _rounds[currentRoundId].itemA.votesCount += 1;
        } else {
            _rounds[currentRoundId].itemB.votesCount += 1;
        }
    }

    function claim(uint256 roundId) external nonReentrant {
        require(!isClaimed(roundId, msg.sender), "already claimed");
        require(!isInVoteTime(roundId), "still in vote time");
        require(!_isNotHaveAnyWinners(roundId), "not have any winners");
        require(_isWinning(roundId, msg.sender), "not a winner");
        require(_isRewardsCalculated(roundId), "rewards not available yet");

        uint256 earned = _rounds[roundId].rewardsPerUser;

        _votes[roundId][msg.sender].earned = earned;
        _votes[roundId][msg.sender].claimedAt = block.timestamp;

        _sendRewardsToUser(msg.sender, earned);
    }

    function completeRound(uint256 roundId) external onlyOwner {
        require(!isInVoteTime(roundId), "still in vote time");
        require(!_isRewardsCalculated(roundId), "round already completed");
        require(!_isNotHaveAnyWinners(roundId), "not have any winners");

        (uint256 itemACount, uint256 itemBCount) = _getVotesCount(roundId);

        uint256 totalRewards = rewardsPool();
        uint256 totalWinners = _getWinningItem(roundId) == RoundItem.A ? itemACount : itemBCount;
        uint256 rewardsPerUser = 0;

        if (totalWinners > 0) {
            rewardsPerUser = totalRewards / totalWinners;
        }

        _rounds[roundId].rewardsPerUser = rewardsPerUser;

        unchecked {
            if (rewardType == RewardType.Token) {
                _unclaimedTokens += rewardsPerUser;
            } else {
                _unclaimedEthers += rewardsPerUser;
            }
        }

        currentRoundId += 1;
    }

    function updateSettings(RewardType rewardType_, uint256 miniumBalance_) external onlyOwner {
        rewardType = rewardType_;
        minimumBalance = miniumBalance_;
    }

    function updateRoundItem(
        uint256 roundId,
        RoundItem item,
        string memory name,
        string memory logo
    ) external onlyOwner {
        if (item == RoundItem.A) {
            _rounds[roundId].itemA.name = name;
            _rounds[roundId].itemA.logo = logo;
        } else {
            _rounds[roundId].itemB.name = name;
            _rounds[roundId].itemB.logo = logo;
        }
    }

    function updateCurrentRoundId(uint256 roundId) external onlyOwner {
        currentRoundId = roundId;
    }

    function addRound(
        uint256 startTime,
        uint256 endTime,
        string memory itemAName,
        string memory itemALogo,
        string memory itemBName,
        string memory itemBLogo
    ) external onlyOwner {
        uint256 roundId = currentRoundId + 1;

        // first time
        if (currentRoundId == 0 && _rounds[0].startTime == 0) {
            roundId = 0;
        }

        _rounds[roundId].startTime = startTime;
        _rounds[roundId].endTime = endTime;
        _rounds[roundId].itemA.name = itemAName;
        _rounds[roundId].itemA.logo = itemALogo;
        _rounds[roundId].itemB.name = itemBName;
        _rounds[roundId].itemB.logo = itemBLogo;
    }

    function decimals() public view returns (uint8) {
        return rewardType == RewardType.Token ? token.decimals() : 18;
    }

    function rewardsPool() public view returns (uint256) {
        unchecked {
            if (rewardType == RewardType.Token) {
                return token.balanceOf(address(this)) - _unclaimedTokens;
            }

            return address(this).balance - _unclaimedEthers;
        }
    }

    function getRound(uint256 roundId) public view returns (Round memory round) {
        round = _rounds[roundId];

        // hide votes count if round is in vote time.
        if (isInVoteTime(roundId)) {
            round.itemA.votesCount = 0;
            round.itemB.votesCount = 0;
        }
    }

    function getCurrentRound() external view returns (Round memory round) {
        round = getRound(currentRoundId);
    }

    function getVote(uint256 roundId, address user) public view returns (Vote memory) {
        return _votes[roundId][user];
    }

    function getVoteOfCurrentRound(address user) external view returns (Vote memory) {
        return getVote(currentRoundId, user);
    }

    function isVoted(uint256 roundId, address user) public view returns (bool) {
        return _votes[roundId][user].createdAt > 0;
    }

    function isClaimed(uint256 roundId, address user) public view returns (bool) {
        return _votes[roundId][user].claimedAt > 0;
    }

    function isInVoteTime(uint256 roundId) public view returns (bool) {
        return _rounds[roundId].startTime <= block.timestamp && _rounds[roundId].endTime >= block.timestamp;
    }

    function isQualifiedToVote(address user) public view returns (bool) {
        return token.balanceOf(user) >= minimumBalance;
    }

    function _isWinning(uint256 roundId, address user) internal view returns (bool) {
        if (!isVoted(roundId, user)) {
            return false;
        }

        return _votes[roundId][user].item == _getWinningItem(roundId);
    }

    function _isNotHaveAnyWinners(uint256 roundId) internal view returns (bool) {
        (uint256 itemACount, uint256 itemBCount) = _getVotesCount(roundId);

        return itemACount == itemBCount;
    }

    function _isRewardsCalculated(uint256 roundId) internal view returns (bool) {
        return _rounds[roundId].rewardsPerUser > 0;
    }

    function _getWinningItem(uint256 roundId) internal view returns (RoundItem) {
        (uint256 itemACount, uint256 itemBCount) = _getVotesCount(roundId);

        return itemACount > itemBCount ? RoundItem.A : RoundItem.B;
    }

    function _getVotesCount(uint256 roundId) internal view returns (uint256 itemACount, uint256 itemBCount) {
        itemACount = _rounds[roundId].itemA.votesCount;
        itemBCount = _rounds[roundId].itemB.votesCount;
    }

    function _sendRewardsToUser(address user, uint256 amount) internal {
        unchecked {
            if (rewardType == RewardType.Token) {
                _unclaimedTokens -= amount;

                token.transfer(user, amount);
            } else {
                _unclaimedEthers -= amount;

                payable(user).sendValue(amount);
            }
        }
    }

    receive() external payable {}
}
