// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// External Imports
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

// Internal Imports
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IPP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Connext_Crosschain_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {PP_Crosschain_v1} from
    "src/modules/paymentProcessor/abstracts/PP_Crosschain_v1.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

/**
 * @title   Connext Cross-chain Payment Processor
 * @notice  Payment processor implementation for cross-chain payments using the Connext protocol
 * @dev     This contract implements cross-chain payment processing via Connext and provides:
 *          - Integration with Connext's EverClear protocol for cross-chain transfers
 *          - WETH handling for native token wrapping
 *          - Implementation of bridge-specific transfer logic
 *          - Payment order processing and validation
 *          - Bridge data storage and retrieval
 *          - Support for Base network (chainId: 8453)
 * @custom:security-contact security@inverter.network
 */
contract PP_Connext_Crosschain_v1 is PP_Crosschain_v1 {
    // Storage Variables
    IEverclearSpoke public everClearSpoke;
    IWETH public weth;

    /// @dev Tracks all details for all payment orders of a paymentReceiver for a specific paymentClient.
    ///      paymentClient => paymentReceiver => intentId.
    mapping(
        address paymentClient => mapping(address recipient => bytes32 intentId)
    ) public intentId;

    /// @dev Tracks failed transfers that can be retried
    ///      paymentClient => recipient => intentId => amount
    mapping(
        address paymentClient
            => mapping(
                address recipient => mapping(bytes32 intentId => uint amount)
            )
    ) public failedTransfers;

    // Errors
    error FailedTransfer();

    // External Functions
    /**
     * @notice Initializes the payment processor module
     * @param orchestrator_ The orchestrator contract address
     * @param metadata Module metadata
     * @param configData ABI encoded configuration data (everClearSpoke and WETH addresses)
     */
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
        (address everClearSpoke_, address weth_) =
            abi.decode(configData, (address, address));

        everClearSpoke = IEverclearSpoke(everClearSpoke_);
        weth = IWETH(weth_);
    }

    /**
     * @notice Processes multiple payment orders through the bridge
     * @param client The payment client contract interface
     * @param executionData Additional data needed for execution (encoded maxFee and TTL)
     */
    function processPayments(
        IERC20PaymentClientBase_v1 client,
        bytes memory executionData
    ) external {
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();

        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData = _executeBridgeTransfer(
                orders[i], executionData, address(client)
            );

            _bridgeData[i] = bridgeData;
            emit PaymentOrderProcessed(
                address(client),
                orders[i].recipient,
                orders[i].paymentToken,
                orders[i].amount,
                orders[i].start,
                orders[i].cliff,
                orders[i].end
            );
            _paymentId++;
            intentId[address(client)][orders[i].recipient] = bytes32(bridgeData);
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    /**
     * @notice Cancels a pending transfer and returns funds to the client
     * @param client The payment client address
     * @param recipient The recipient address
     * @param pendingIntentId The intentId to cancel
     * @param order The payment order details
     */
    function cancelTransfer(
        address client,
        address recipient,
        bytes32 pendingIntentId,
        IERC20PaymentClientBase_v1.PaymentOrder memory order
    ) external {
        _validateTransferRequest(client, recipient, pendingIntentId);
        _cleanupFailedTransfer(client, recipient, pendingIntentId);

        if (!IERC20(order.paymentToken).transfer(recipient, order.amount)) {
            revert FailedTransfer();
        }

        emit TransferCancelled(client, recipient, pendingIntentId, order.amount);
    }

    /**
     * @notice Retries a previously failed transfer
     * @param client The payment client address
     * @param recipient The recipient address
     * @param pendingIntentId The failed intent ID
     * @param order The payment order details
     * @param executionData New execution data for retry
     */
    function retryFailedTransfer(
        address client,
        address recipient,
        bytes32 pendingIntentId,
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external {
        _validateTransferRequest(client, recipient, pendingIntentId);

        bytes32 newIntentId = _createCrossChainIntent(order, executionData);
        if (newIntentId == bytes32(0)) {
            revert Module__PP_Crosschain__MessageDeliveryFailed(
                8453, 8453, executionData
            );
        }

        _cleanupFailedTransfer(client, recipient, pendingIntentId);
        intentId[client][recipient] = newIntentId;
    }

    // Public Functions
    /**
     * @notice Retrieves the bridge data for a specific payment ID
     * @param paymentId The unique identifier of the payment
     * @return The bridge data associated with the payment
     */
    function getBridgeData(uint paymentId)
        public
        view
        override
        returns (bytes memory)
    {
        return _bridgeData[paymentId];
    }

    // Internal Functions
    /**
     * @dev Execute the cross-chain bridge transfer
     * @param order The payment order containing transfer details
     * @param executionData Additional execution parameters
     * @param client The client address
     * @return bridgeData Data returned by the bridge implementation
     */
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData,
        address client
    ) internal returns (bytes memory) {
        bytes32 _intentId = _createCrossChainIntent(order, executionData);

        if (_intentId == bytes32(0)) {
            failedTransfers[client][order.recipient][_intentId] = order.amount;
            intentId[client][order.recipient] = _intentId;
            emit TransferFailed(
                client, order.recipient, _intentId, order.amount
            );
        }

        return abi.encode(_intentId);
    }

    /**
     * @dev Creates a new cross-chain intent for payment transfer
     * @param order The payment order details
     * @param executionData Additional execution parameters
     * @return The ID of the created intent
     */
    function _createCrossChainIntent(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal returns (bytes32) {
        _validateOrder(order);

        if (executionData.length == 0) {
            revert
                ICrossChainBase_v1
                .Module__CrossChainBase_InvalidExecutionData();
        }
        (uint maxFee, uint ttl) = abi.decode(executionData, (uint, uint));
        if (ttl == 0) {
            revert
                IPP_Connext_Crosschain_v1
                .Module__PP_Connext_Crosschain__InvalidTTL();
        }

        IERC20(order.paymentToken).transferFrom(
            msg.sender, address(this), order.amount
        );
        IERC20(order.paymentToken).approve(
            address(everClearSpoke), order.amount
        );

        uint32[] memory destinations = new uint32[](1);
        destinations[0] = 8453;

        return everClearSpoke.newIntent(
            destinations,
            order.recipient,
            order.paymentToken,
            address(weth),
            order.amount,
            uint24(maxFee),
            uint48(ttl),
            ""
        );
    }

    /**
     * @dev Validates a transfer request
     * @param client The payment client address
     * @param recipient The recipient address
     * @param pendingIntentId The intent ID to validate
     * @return The amount of the failed transfer
     */
    function _validateTransferRequest(
        address client,
        address recipient,
        bytes32 pendingIntentId
    ) internal view returns (uint) {
        if (msg.sender != client) {
            revert Module__InvalidAddress();
        }

        if (intentId[client][recipient] != pendingIntentId) {
            revert Module__PP_Crosschain__InvalidIntentId();
        }

        uint failedAmount = failedTransfers[client][recipient][pendingIntentId];
        if (failedAmount == 0) {
            revert Module__CrossChainBase__InvalidAmount();
        }

        return failedAmount;
    }

    /**
     * @dev Cleans up storage after handling a failed transfer
     * @param client The payment client address
     * @param recipient The recipient address
     * @param pendingIntentId The intent ID to clean up
     */
    function _cleanupFailedTransfer(
        address client,
        address recipient,
        bytes32 pendingIntentId
    ) internal {
        delete intentId[client][recipient];
        delete failedTransfers[client][recipient][pendingIntentId];
    }

    /**
     * @dev Validates a payment order
     * @param order The payment order to validate
     */
    function _validateOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order
    ) internal pure {
        if (order.amount == 0) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount();
        }
        if (order.recipient == address(0)) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient();
        }
    }
}
