// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VRFv2Consumer} from "./chainlink/VRFv2Consumer.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";

contract ApeBlendr is ERC20, VRFv2Consumer {
    constructor(
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        address _vrfCordinator
    )
        ERC20("ApeBlendr", "APEd")
        VRFv2Consumer(_subscriptionId, _keyHash, _callbackGasLimit, _requestConfirmations, _numWords, _vrfCordinator)
    {}

    function requestRandomWords() internal returns (uint256 _userRequestId) {
        _userRequestId =
            COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {}
}
