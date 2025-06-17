// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../interfaces/INativeVRFConsumer.sol";
import "../NativeVRFCoordinator.sol";

/**
 * @title NativeVRFConsumerExample
 * @dev Example contract showing how to consume randomness from NativeVRF through the coordinator
 */
contract NativeVRFConsumerExample is INativeVRFConsumer {
    // The VRF Coordinator contract
    NativeVRFCoordinator public immutable coordinator;
    
    // Callback gas limit for fulfillment
    uint256 public callbackGasLimit = 100000;
    
    // Mapping of request IDs to random results
    mapping(uint256 => uint256) public randomResults;
    
    // Mapping to track if a request has been fulfilled
    mapping(uint256 => bool) public fulfilled;
    
    // Events
    event RandomnessRequested(uint256 indexed requestId);
    event RandomnessFulfilled(uint256 indexed requestId, uint256 randomness);
    
    /**
     * @dev Constructor sets the coordinator address
     */
    constructor(address _coordinator) {
        coordinator = NativeVRFCoordinator(_coordinator);
    }
    
    /**
     * @dev Register this contract with the coordinator
     * Must be called after contract deployment
     */
    function registerWithCoordinator() external {
        coordinator.registerConsumer();
    }
    
    /**
     * @dev Fund this contract's balance in the coordinator
     */
    function fundContract() external payable {
        // Forward funds to the coordinator
        coordinator.fundConsumer{value: msg.value}();
    }
    
    /**
     * @dev Request randomness from the coordinator
     */
    function requestRandomness() external returns (uint256) {
        // Request randomness from the coordinator
        uint256 requestId = coordinator.requestRandomness(callbackGasLimit);
        
        emit RandomnessRequested(requestId);
        return requestId;
    }
    
    /**
     * @dev Callback function called by the coordinator when randomness is fulfilled
     * @notice Only the coordinator can call this function
     */
    function rawFulfillRandomness(uint256 _requestId, uint256 _randomness) external override {
        // Ensure only the coordinator can call this function
        require(msg.sender == address(coordinator), "Only coordinator can fulfill");
        
        // Store the random result
        randomResults[_requestId] = _randomness;
        fulfilled[_requestId] = true;
        
        emit RandomnessFulfilled(_requestId, _randomness);
    }
    
    /**
     * @dev Example function showing how to use the random number
     * Returns a number between 1 and _max
     */
    function getRandomNumber(uint256 _requestId, uint256 _max) external view returns (uint256) {
        require(fulfilled[_requestId], "Request not fulfilled");
        require(_max > 0, "Max must be greater than 0");
        
        // Use the random result to generate a number between 1 and _max
        return (randomResults[_requestId] % _max) + 1;
    }
    
    /**
     * @dev Set the callback gas limit
     */
    function setCallbackGasLimit(uint256 _callbackGasLimit) external {
        callbackGasLimit = _callbackGasLimit;
    }
}
