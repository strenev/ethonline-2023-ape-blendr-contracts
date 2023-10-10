// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";

contract ApeBlendr is ERC20 {
    constructor() ERC20("ApeBlendr", "APEd") {}
}
