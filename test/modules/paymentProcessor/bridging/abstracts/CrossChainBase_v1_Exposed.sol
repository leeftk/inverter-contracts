// SPDX-License-Identifier: LGPL-3.0-only

// Internal Dependencies
//import {PP_CrossChain_v1} from "src/templates/modules/PP_Template_v1.sol";
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

contract CrossChainBase_v1_Exposed is CrossChainBase_v1 {
    constructor(uint chainId_) CrossChainBase_v1() {}

    /// @notice Implementation of the bridge transfer logic using EverClear
    ///// @inheritdoc CrossChainBase_v1

    function exposed_executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external payable returns (bytes memory) {
        return _executeBridgeTransfer(order, executionData);
    }
}
