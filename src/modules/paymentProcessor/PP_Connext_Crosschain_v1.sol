pragma solidity ^0.8.20;

import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IPP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Connext_Crosschain_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {PP_Crosschain_v1} from
    "src/modules/paymentProcessor/abstracts/PP_Crosschain_v1.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";

/**
 * @title   Connext Cross-chain Payment Processor
 *
 * @notice  Payment processor implementation for cross-chain payments using the Connext protocol.
 *
 * @dev     This contract implements cross-chain payment processing via Connext and provides:
 *          - Integration with Connext's EverClear protocol for cross-chain transfers
 *          - WETH handling for native token wrapping
 *          - Implementation of bridge-specific transfer logic
 *          - Payment order processing and validation
 *          - Bridge data storage and retrieval
 *          - Support for Base network (chainId: 8453)
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network
 */
contract PP_Connext_Crosschain_v1 is PP_Crosschain_v1 {
    IEverclearSpoke public everClearSpoke;
    IWETH public weth;

    /// @notice Initializes the payment processor module
    /// @param orchestrator_ The address of the orchestrator contract
    /// @param metadata Module metadata
    /// @param configData ABI encoded configuration data containing everClearSpoke and WETH addresses
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

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal override returns (bytes memory) {
        //@notice call the connextBridgeLogic to execute the bridge transfer
        bytes32 intentId = xcall(order, executionData);
        if (intentId == bytes32(0)) {
            revert Module__PP_Crosschain__MessageDeliveryFailed(
                8453, 8453, executionData
            );
        }
        return abi.encode(intentId);
    }

    /// @notice Processes multiple payment orders through the bridge
    /// @param client The payment client contract interface
    /// @param executionData Additional data needed for execution (encoded maxFee and TTL)
    function processPayments(
        IERC20PaymentClientBase_v1 client,
        bytes memory executionData
    ) external {
        // Collect orders from the client
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();

        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData =
                _executeBridgeTransfer(orders[i], executionData);

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

            // Inform the client about the processed amount
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    /// @notice Executes a cross-chain transfer through the Connext bridge
    /// @param order The payment order to be processed
    /// @param executionData Encoded data containing maxFee and TTL for the transfer
    /// @return intentId The unique identifier for the cross-chain transfer
    function xcall(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal returns (bytes32) {
        if (executionData.length == 0) {
            revert
                ICrossChainBase_v1
                .Module__CrossChainBase_InvalidExecutionData();
        }

        if (order.amount == 0) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount();
        }
        if (order.recipient == address(0)) {
            revert ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient();
        }
        // Decode the execution data
        (uint maxFee, uint ttl) = abi.decode(executionData, (uint, uint));

        if (ttl == 0) {
            revert
                IPP_Connext_Crosschain_v1
                .Module__PP_Connext_Crosschain__InvalidTTL();
        }

        // Wrap ETH into WETH to send with the xcall
        IERC20(order.paymentToken).transferFrom(
            msg.sender, address(this), order.amount
        );

        // This contract approves transfer to EverClearSpoke
        IERC20(order.paymentToken).approve(
            address(everClearSpoke), order.amount
        );

        // Create destinations array with the target chain
        uint32[] memory destinations = new uint32[](1);
        destinations[0] = 8453;
        // @note -> hardcode for now -> order.destinationChainId when the
        // new struct is created for us

        // Call newIntent on the EverClearSpoke contract
        (intentId,) = everClearSpoke.newIntent(
            destinations,
            order.recipient,
            order.paymentToken,
            address(weth),
            order.amount,
            uint24(maxFee),
            uint48(ttl),
            ""
        );

        return intentId;
    }

    /// @notice Retrieves the bridge data for a specific payment ID
    /// @param paymentId The unique identifier of the payment
    /// @return The bridge data associated with the payment (encoded intentId)
    function getBridgeData(uint paymentId)
        public
        view
        override
        returns (bytes memory)
    {
        return _bridgeData[paymentId];
    }
}
