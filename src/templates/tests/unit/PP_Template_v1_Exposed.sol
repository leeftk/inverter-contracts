// SPDX-License-Identifier: LGPL-3.0-only
<<<<<<< HEAD
pragma solidity ^0.8.0;

// Internal
import {PP_Template_v1} from "src/templates/modules/PP_Template_v1.sol";

// Access Mock of the PP_Template_v1 contract for Testing.
contract PP_Template_v1_Exposed is PP_Template_v1 {
    // Use the `exposed_` prefix for functions to expose internal contract for
    // testing.

    function exposed_setPayoutAmountMultiplier(uint newPayoutAmountMultiplier_)
        external
    {
        _setPayoutAmountMultiplier(newPayoutAmountMultiplier_);
    }

    function exposed_validPaymentReceiver(address receiver_)
        external
        view
        returns (bool validPaymentReceiver_)
    {
        validPaymentReceiver_ = _validPaymentReceiver(receiver_);
    }

    function exposed_ensureValidClient(address client_) external view {
        _ensureValidClient(client_);
    }
}
=======
pragma solidity 0.8.23;

// // Internal Dependencies
// import { PP_CrossChain_v1 } from "src/templates/modules/PP_Template_v1.sol";
// import { IERC20PaymentClientBase_v1 } from "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
// import { IEverclearSpoke } from "./interfaces/IEverclearSpoke.sol";

// interface IWETH {
//     function deposit() external payable;
//     function approve(address spender, uint256 amount) external returns (bool);
// }

// contract PP_CrossChain_v1_Exposed is PP_CrossChain_v1 {

//     IEverclearSpoke public everClearSpoke;
//     IWETH public weth;

//     /// @notice Implementation of the bridge transfer logic using EverClear
//     /// @inheritdoc PP_CrossChain_v1
//     function _executeBridgeTransfer(
//         IERC20PaymentClientBase_v1.PaymentOrder memory order,
//         bytes memory executionData
//     ) internal override returns (bytes memory) {
//         (uint256 maxFee, uint256 ttl, address inputAsset, address outputAsset) = 
//             abi.decode(executionData, (uint256, uint256, address, address));

//         // Wrap ETH into WETH to send with the xcall
//         weth.deposit{value: msg.value}();

//         // This contract approves transfer to EverClear
//         weth.approve(address(everClearSpoke), order.amount);

//         // Create destinations array with the target chain
//         uint32[] memory destinations = new uint32[](1);
//         destinations[0] = 1;

//         // Call newIntent on the EverClearSpoke contract
//         (bytes32 intentId,) = everClearSpoke.newIntent(
//             destinations,
//             order.recipient, // Changed from msg.sender to order.recipient
//             inputAsset,
//             outputAsset,
//             order.amount,
//             uint24(maxFee),
//             uint48(ttl),
//             "" // empty data field
//         );

//         return abi.encode(intentId);
//     }

//     function processPayments(IERC20PaymentClientBase_v1 client_, bytes memory executionData) 
//         external 
//         override 
//         validClient(address(client_))
//     {
//         super.processPayments(client_, executionData);
//     }

  

// }
>>>>>>> 79edbd43 (add cross-chain module, contracts compile)
