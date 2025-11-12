// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MockOracle {
    int256 private price = 2000e8; // 2000 USD with 8 decimals

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, price, 0, block.timestamp, 0);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function setPrice(int256 newPrice) external {
        price = newPrice;
    }
}
