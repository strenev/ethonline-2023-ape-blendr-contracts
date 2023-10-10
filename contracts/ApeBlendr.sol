// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {VRFv2Consumer} from "./chainlink/VRFv2Consumer.sol";
import {SortitionSumTreeFactory} from "./lib/SortitionSumTreeFactory.sol";
import {UniformRandomNumber} from "./lib/UniformRandomNumber.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";

contract ApeBlendr is ERC20, VRFv2Consumer, Ownable {
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

    struct ApeDraw {
        address winner;
        uint256 apeCoinAward;
        bool isFinalised;
        uint256 blockNumber;
    }

    address public immutable apeCoin;
    address public immutable apeCoinStaking;

    uint256 public apeBlendrFeeBps;
    uint256 public epochSeconds;
    uint256 public epochStartedAt;
    uint256 public totalPrizeDraws;

    bool public awardInProgress;

    mapping(uint256 => ApeDraw) public apeDraws;

    bytes32 private constant TREE_KEY = keccak256("ApeBlendr/ApeCoin");
    uint256 private constant MAX_TREE_LEAVES = 5;
    uint256 private constant APE_COIN_PRECISION = 1e18;

    SortitionSumTreeFactory.SortitionSumTrees internal sortitionSumTrees;

    constructor(
        address _apeCoin,
        address _apeCoinStaking,
        uint256 _apeBlendrFeeBps,
        uint256 _epochSeconds,
        uint256 _epochStartedAt,
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        address _vrfCordinator
    )
        ERC20("ApeBlendr", "APEd")
        Ownable(msg.sender)
        VRFv2Consumer(_subscriptionId, _keyHash, _callbackGasLimit, _requestConfirmations, _numWords, _vrfCordinator)
    {
        apeCoin = _apeCoin;
        apeCoinStaking = _apeCoinStaking;
        apeBlendrFeeBps = _apeBlendrFeeBps;
        epochSeconds = _epochSeconds;
        epochStartedAt = _epochStartedAt;

        sortitionSumTrees.createTree(TREE_KEY, MAX_TREE_LEAVES);
    }

    function getApeCoinStake() public view returns (IApeCoinStaking.DashboardStake memory) {
        return IApeCoinStaking(apeCoinStaking).getApeCoinStake(address(this));
    }

    function epochEndAt() public view returns (uint256) {
        return epochStartedAt + epochSeconds;
    }

    function hasEpochEnded() external view returns (bool) {
        return block.timestamp >= epochEndAt();
    }

    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    function _calculateNextEpochStartTime(uint256 currentTime) internal view returns (uint256) {
        uint256 elapsedEpochs = (currentTime - epochStartedAt) / epochSeconds;
        return epochStartedAt + (elapsedEpochs * epochSeconds);
    }

    function _checkEpochHasNotEnded() internal view {
        if (getCurrentTime() > epochEndAt()) {
            revert CurrentEpochHasEnded();
        }
    }

    function _checkEpochHasEnded() internal view {
        if (getCurrentTime() < epochEndAt()) {
            revert CurrentEpochHasNotEnded();
        }
    }

    function _checkAwardingInProgress() internal view {
        if (awardInProgress) revert AwardingInProgress();
    }

    function _drawWinner(uint256 randomWord) internal view returns (address winner) {
        uint256 bound = totalSupply();
        if (bound == 0) {
            winner = address(0);
        } else {
            uint256 token = UniformRandomNumber.uniform(randomWord, bound);
            winner = address(uint160(uint256(sortitionSumTrees.draw(TREE_KEY, token))));
        }
    }

    function _settleApeCoinAwardForDraw(uint256 requestId, uint256 randomWord) internal {
        ApeDraw storage apeDraw = apeDraws[requestId];

        apeDraw.winner = _drawWinner(randomWord);
        apeDraw.isFinalised = true;
        apeDraw.blockNumber = block.number;

        ++totalPrizeDraws;

        _finalizeEpoch();

        if (apeDraw.winner != address(0) && apeDraw.apeCoinAward != 0) {
            _mint(apeDraw.winner, apeDraw.apeCoinAward);
        }

        emit AwardingFinished(requestId, apeDraw.apeCoinAward, apeDraw.winner);
    }

    function _finalizeEpoch() internal {
        awardInProgress = false;
        epochStartedAt = _calculateNextEpochStartTime(getCurrentTime());

        emit EpochEnded(epochStartedAt);
    }

    function enterApeBlendr(uint256 amount) external {
        _checkAwardingInProgress();
        _mint(msg.sender, amount);

        IERC20(apeCoin).transferFrom(msg.sender, address(this), amount);
        IERC20(apeCoin).approve(apeCoinStaking, amount);
        IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(amount);

        emit ApeBlendrEntered(msg.sender, amount);
    }

    function exitApeBlendr(uint256 amount) external {
        _checkAwardingInProgress();
        _burn(msg.sender, amount);

        IApeCoinStaking(apeCoinStaking).withdrawApeCoin(amount, msg.sender);

        emit ApeBlendrExited(msg.sender, amount);
    }

    function startApeCoinAwardingProcess() external {
        _checkEpochHasEnded();
        _checkAwardingInProgress();

        awardInProgress = true;

        IApeCoinStaking.DashboardStake memory apeStakeInfo = getApeCoinStake();

        uint256 totalSupply = totalSupply();
        uint256 totalApeCoinBalance = apeStakeInfo.deposited + apeStakeInfo.unclaimed;

        uint256 awardForCurrentDraw = totalApeCoinBalance > totalSupply ? (totalApeCoinBalance - totalSupply) : 0;
        if (awardForCurrentDraw > 0) {
            uint256 requestId = requestRandomWords();

            apeDraws[requestId].apeCoinAward = awardForCurrentDraw;

            if (awardForCurrentDraw >= 1 * (APE_COIN_PRECISION)) {
                IApeCoinStaking(apeCoinStaking).claimSelfApeCoin();

                IERC20(apeCoin).approve(apeCoinStaking, awardForCurrentDraw);
                IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(awardForCurrentDraw);
            }

            if (awardForCurrentDraw < 1 * (APE_COIN_PRECISION)) {
                IApeCoinStaking(apeCoinStaking).claimSelfApeCoin();

                IApeCoinStaking(apeCoinStaking).withdrawApeCoin(
                    (1 * (APE_COIN_PRECISION) - awardForCurrentDraw), address(this)
                );

                IERC20(apeCoin).approve(apeCoinStaking, 1 * (APE_COIN_PRECISION));
                IApeCoinStaking(apeCoinStaking).depositSelfApeCoin(1 * (APE_COIN_PRECISION));
            }

            emit AwardingStarted(requestId, awardForCurrentDraw);
        } else {
            _finalizeEpoch();
            emit NoAwardForCurrentEpoch();
        }
    }

    function requestRandomWords() internal returns (uint256 _userRequestId) {
        _userRequestId =
            COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        _settleApeCoinAwardForDraw(requestId, randomWords[0]);
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0)) {
            uint256 fromBalance = balanceOf(from) - amount;
            sortitionSumTrees.set(TREE_KEY, fromBalance, bytes32(uint256(uint160(from))));
        }

        if (to != address(0)) {
            uint256 toBalance = balanceOf(to) + amount;
            sortitionSumTrees.set(TREE_KEY, toBalance, bytes32(uint256(uint160(to))));
        }

        super._update(from, to, amount);
    }

    event ApeBlendrEntered(address player, uint256 amount);
    event ApeBlendrExited(address player, uint256 amount);
    event EpochEnded(uint256 newEpochStartedAt);
    event AwardingStarted(uint256 requestId, uint256 awardForDraw);
    event AwardingFinished(uint256 requestId, uint256 awardForDraw, address winner);
    event NoAwardForCurrentEpoch();

    error CurrentEpochHasEnded();
    error CurrentEpochHasNotEnded();
    error AwardingInProgress();
    error UnauthorizedTransfer();
}
