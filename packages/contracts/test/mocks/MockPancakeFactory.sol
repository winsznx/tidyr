// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPancakeFactory} from "../../src/interfaces/IPancakeFactory.sol";

contract MockPancakeFactory is IPancakeFactory {
    mapping(address => mapping(address => address)) public pairs;

    function setPair(address tokenA, address tokenB, address pair) external {
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
}
