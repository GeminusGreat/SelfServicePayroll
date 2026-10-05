// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Mock Chainlink ETH/USD price feed used for testing.
 *
 * @dev
 * Chainlink normally returns prices with 8 decimals.
 *
 * Example:
 * $2,000 ETH = 2000e8
 */
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 public immutable override decimals;

    string public override description;

    uint256 public override version;

    int256 private s_answer;

    uint80 private s_roundId;

    uint256 private s_startedAt;

    uint256 private s_updatedAt;

    constructor(
        uint8 _decimals,
        int256 _initialAnswer
    ) {
        decimals = _decimals;
        description = "Mock ETH / USD Price Feed";
        version = 1;

        s_answer = _initialAnswer;
        s_roundId = 1;
        s_startedAt = block.timestamp;
        s_updatedAt = block.timestamp;
    }

    /**
     * @notice Updates the ETH/USD price.
     *
     * @param newAnswer New price using Chainlink decimals.
     *
     * Example:
     * 2000 USD = 2000e8
     */
    function updateAnswer(
        int256 newAnswer
    ) external {
        s_answer = newAnswer;

        s_roundId++;

        s_startedAt = block.timestamp;
        s_updatedAt = block.timestamp;
    }

    /**
     * @notice Returns data for a specific round.
     */
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            s_answer,
            s_startedAt,
            s_updatedAt,
            s_roundId
        );
    }

    /**
     * @notice Returns the latest ETH/USD price data.
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            s_roundId,
            s_answer,
            s_startedAt,
            s_updatedAt,
            s_roundId
        );
    }
}