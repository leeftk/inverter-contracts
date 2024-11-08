pragma solidity ^0.8.20;

import {CrosschainBase_v1} from "src/templates/modules/CrosschainBase_v1.sol";
import {ICrossChainBase_v1} from "src/templates/modules/ICrosschainBase_v1.sol";
import {ConnextBridgeLogic} from "./ConnextBridgeLogic.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

contract PP_Connext_Crosschain_v1 is CrosschainBase_v1 {
    ConnextBridgeLogic public connextBridgeLogic;

    constructor(uint chainId_, address connextBridgeLogic_)
        CrosschainBase_v1()
    {
        connextBridgeLogic = ConnextBridgeLogic(connextBridgeLogic_);
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
        bytes32 intentId = connextBridgeLogic.xcall(order, executionData);
        return abi.encode(intentId);
    }

    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        override
    {
        // To encode maxFee and ttl:
        uint maxFee = 0;
        uint ttl = 0;
        bytes memory executionData = abi.encode(maxFee, ttl);

        // Collect orders from the client
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        (orders,,) = client.collectPaymentOrders();

        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData =
                _executeBridgeTransfer(orders[i], executionData);
            _bridgeData[_paymentId] = bridgeData;

            emit PaymentProcessed(
                _paymentId,
                orders[i].recipient,
                orders[i].paymentToken,
                orders[i].amount
            );
            _paymentId++;

            // Inform the client about the processed amount
            client.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }
}
