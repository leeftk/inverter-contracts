// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
//import {PP_CrossChain_v1} from "src/templates/modules/PP_Template_v1.sol";
import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/bridging/abstracts/CrosschainBase_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

contract CrosschainBase_v1_Exposed is CrosschainBase_v1 {
    /// @notice Implementation of the bridge transfer logic using EverClear
    ///// @inheritdoc CrosschainBase_v1
    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external payable returns (bytes memory) {
        return _executeBridgeTransfer(order, executionData);
    }
}