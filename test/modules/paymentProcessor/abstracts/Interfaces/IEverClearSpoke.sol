// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEverclearSpoke
 * @notice Interface for the Everclear spoke contract
 */
interface IEverclearSpoke {
    /*///////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Intent {
        bytes32 initiator;
        bytes32 receiver;
        bytes32 inputAsset;
        bytes32 outputAsset;
        uint amount;
        uint24 maxFee;
        uint32 origin;
        uint32[] destinations;
        uint nonce;
        uint48 timestamp;
        uint48 ttl;
        bytes data;
    }

    struct FillMessage {
        bytes32 intentId;
        bytes32 initiator;
        bytes32 solver;
        uint48 executionTimestamp;
        uint24 fee;
    }

    struct Permit2Params {
        uint nonce;
        uint deadline;
        bytes signature;
    }

    struct SpokeInitializationParams {
        address gateway;
        address messageReceiver;
        address lighthouse;
        address watchtower;
        address callExecutor;
        uint32 hubDomain;
        address owner;
    }

    /*///////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(SpokeInitializationParams calldata init) external;
    function pause() external;
    function unpause() external;
    function updateSecurityModule(address newSecurityModule) external;
    function newIntent(
        uint32[] memory destinations,
        address to,
        address inputAsset,
        address outputAsset,
        uint amount,
        uint24 maxFee,
        uint48 ttl,
        bytes calldata data
    ) external returns (bytes32 intentId, Intent memory intent);
    function newIntent(
        uint32[] memory destinations,
        address to,
        address inputAsset,
        address outputAsset,
        uint amount,
        uint24 maxFee,
        uint48 ttl,
        bytes calldata data,
        Permit2Params calldata permit2Params
    ) external returns (bytes32 intentId, Intent memory intent);
    function fillIntent(Intent calldata intent, uint24 fee)
        external
        returns (FillMessage memory fillMessage);
    function fillIntentForSolver(
        address solver,
        Intent calldata intent,
        uint nonce,
        uint24 fee,
        bytes calldata signature
    ) external returns (FillMessage memory fillMessage);
    function processIntentQueue(Intent[] calldata intents) external payable;
    function processFillQueue(uint32 amount) external payable;
    function processIntentQueueViaRelayer(
        uint32 domain,
        Intent[] calldata intents,
        address relayer,
        uint ttl,
        uint nonce,
        uint bufferBPS,
        bytes calldata signature
    ) external;
    function processFillQueueViaRelayer(
        uint32 domain,
        uint32 amount,
        address relayer,
        uint ttl,
        uint nonce,
        uint bufferBPS,
        bytes calldata signature
    ) external;
    function deposit(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function updateGateway(address newGateway) external;
    function updateMessageReceiver(address newMessageReceiver) external;
    function authorizeGasReceiver(address receiver, bool authorized) external;
    function updateMessageGasLimit(uint newGasLimit) external;
    function executeIntentCalldata(Intent calldata intent) external;
}
