// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @title INativeVRFConsumer
 * @dev Interface for contracts using NativeVRF randomness
 */
interface INativeVRFConsumer {
    /**
     * @dev Called by NativeVRFCoordinator when the randomness is fulfilled
     * @param requestId The ID of the request being fulfilled
     * @param randomness The random result
     */
    function rawFulfillRandomness(uint256 requestId, uint256 randomness) external;
}
