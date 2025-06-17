// SPDX-License-Identifier: MIT
// Native VRF Contracts (last updated v0.0.1) (NativeVRFCoordinator.sol)
pragma solidity 0.8.4;

import "./NativeVRF.sol";
import "./interfaces/INativeVRFConsumer.sol";

/**
 * @title NativeVRFCoordinator
 * @dev This contract handles the payment and coordination between VRF consumers and providers.
 * Consumers register and deposit funds to cover gas costs for their VRF requests.
 * When a provider fulfills a request, they are compensated for the gas used plus a fixed premium.
 */
contract NativeVRFCoordinator {
    // The NativeVRF contract
    NativeVRF public immutable nativeVRF;
    
    // Fixed premium paid to providers on top of gas costs
    uint256 public fixedPremium = 0.0001 ether; // Fixed premium amount
    
    // Estimated gas used for callback fulfillment
    uint256 public callbackGasLimit = 200000;
    
    // Consumer registration and balances
    mapping(address => bool) public registeredConsumers;
    mapping(address => uint256) public consumerBalances;
    
    // Request tracking
    mapping(uint256 => RequestConfig) public requestConfigs;
    
    struct RequestConfig {
        address consumer;      // Consumer contract address
        uint256 callbackGas;   // Gas limit for callback
        bool fulfilled;        // Whether the request has been fulfilled
    }
    
    // Events
    event ConsumerRegistered(address indexed consumer);
    event ConsumerFunded(address indexed consumer, uint256 amount);
    event RequestInitiated(uint256 indexed requestId, address indexed consumer, uint256 callbackGas);
    event RequestFulfilled(uint256 indexed requestId, address indexed provider, uint256 payment);
    
    /**
     * @dev Constructor sets the NativeVRF contract address
     */
    constructor(address _nativeVRF) {
        nativeVRF = NativeVRF(_nativeVRF);
    }
    
    /**
     * @dev Register a consumer contract
     */
    function registerConsumer() external {
        registeredConsumers[msg.sender] = true;
        emit ConsumerRegistered(msg.sender);
    }
    
    /**
     * @dev Fund a consumer's account
     */
    function fundConsumer() external payable {
        require(msg.value > 0, "Must send some ETH");
        consumerBalances[msg.sender] += msg.value;
        emit ConsumerFunded(msg.sender, msg.value);
    }
    
    /**
     * @dev Request randomness on behalf of a consumer
     * @param _callbackGasLimit Gas limit for the callback function
     */
    function requestRandomness(uint256 _callbackGasLimit) external returns (uint256) {
        require(registeredConsumers[msg.sender], "Consumer not registered");
        
        // Calculate the cost for this request
        uint256 gasCost = calculateGasCost(_callbackGasLimit);
        require(consumerBalances[msg.sender] >= gasCost, "Insufficient consumer balance");
        
        // Reserve the funds
        consumerBalances[msg.sender] -= gasCost;
        
        // Request randomness from NativeVRF
        uint256[] memory requestIds = nativeVRF.requestRandom(1);
        uint256 requestId = requestIds[0];
        
        // Store request configuration
        requestConfigs[requestId] = RequestConfig({
            consumer: msg.sender,
            callbackGas: _callbackGasLimit,
            fulfilled: false
        });
        
        emit RequestInitiated(requestId, msg.sender, _callbackGasLimit);
        
        return requestId;
    }
    
    /**
     * @dev Fulfill randomness and compensate the provider
     * @param _requestId The request ID to fulfill
     * @param _randInput The random input
     * @param _signature The signature
     */
    function fulfillRandomness(uint256 _requestId, uint256 _randInput, bytes memory _signature) external {
        // Ensure request exists and hasn't been fulfilled
        RequestConfig storage config = requestConfigs[_requestId];
        require(config.consumer != address(0), "Request not found");
        require(!config.fulfilled, "Request already fulfilled");
        
        // Record gas before fulfillment
        uint256 gasStart = gasleft();
        
        // Fulfill randomness in NativeVRF
        // Create dynamic arrays with single elements
        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = _requestId;
        
        uint256[] memory randInputs = new uint256[](1);
        randInputs[0] = _randInput;
        
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signature;
        
        nativeVRF.fullfillRandomness(requestIds, randInputs, signatures);
        
        // Get the random result
        uint256 randomResult = nativeVRF.randomResults(_requestId);
        
        // Call the consumer's callback
        INativeVRFConsumer(config.consumer).rawFulfillRandomness(_requestId, randomResult);
        
        // Calculate gas used and payment
        uint256 gasUsed = gasStart - gasleft();
        uint256 actualGasUsed = gasUsed > config.callbackGas ? config.callbackGas : gasUsed;
        uint256 payment = calculatePayment(actualGasUsed);
        
        // Mark as fulfilled
        config.fulfilled = true;
        
        // Pay the provider
        (bool success, ) = payable(msg.sender).call{value: payment}("");
        require(success, "Transfer failed");
        
        emit RequestFulfilled(_requestId, msg.sender, payment);
    }
    
    /**
     * @dev Calculate the cost for a request based on gas limit
     */
    function calculateGasCost(uint256 _callbackGasLimit) public view returns (uint256) {
        uint256 gasLimit = _callbackGasLimit > 0 ? _callbackGasLimit : callbackGasLimit;
        return tx.gasprice * gasLimit;
    }
    
    /**
     * @dev Calculate payment for a provider including premium
     */
    function calculatePayment(uint256 _gasUsed) public view returns (uint256) {
        uint256 baseCost = tx.gasprice * _gasUsed;
        return baseCost + fixedPremium;
    }
    
    /**
     * @dev Update the fixed premium amount (requires governance)
     */
    function setFixedPremium(uint256 _fixedPremium) external {
        // TODO: Add governance control
        fixedPremium = _fixedPremium;
    }
    
    /**
     * @dev Update the default callback gas limit (requires governance)
     */
    function setCallbackGasLimit(uint256 _callbackGasLimit) external {
        // TODO: Add governance control
        callbackGasLimit = _callbackGasLimit;
    }
    
    /**
     * @dev Allow consumers to withdraw unused funds
     */
    function withdrawFunds(uint256 _amount) external {
        require(consumerBalances[msg.sender] >= _amount, "Insufficient balance");
        consumerBalances[msg.sender] -= _amount;
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");
    }
}
