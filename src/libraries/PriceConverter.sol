// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

error InvalidPrice();
error StalePrice();

/**
 * @title PriceConverter
 * @notice Converts between ETH (wei) and USD using a live Chainlink price feed.
 * @dev All USD amounts in this library use 18 decimals, same as wei, so $100 = 100e18.
 *      Chainlink feeds report price with 8 decimals, so we scale by 1e10 to line them up.
 */
library PriceConverter {
    // Returns the current ETH/USD price, scaled to 18 decimals.
    // Reverts if the price is zero, negative, or has not been updated for 3 hours.
    function getPrice(
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > 3 hours) revert StalePrice();

        // answer comes back with 8 decimals (e.g. 3000.00000000 as 300000000000)
        // multiplying by 1e10 turns that into 18 decimals so it lines up with wei math
        return uint256(answer) * 1e10;
    }

    // How much is `ethAmount` wei worth in USD (18 decimals) right now?
    function ethToUsd(
        uint256 ethAmount,
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        return (ethPrice * ethAmount) / 1e18;
    }

    // How much ETH (in wei) is needed right now to equal `usdAmount` (18 decimals)?
    function usdToEth(
        uint256 usdAmount,
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        return (usdAmount * 1e18) / ethPrice;
    }
}
