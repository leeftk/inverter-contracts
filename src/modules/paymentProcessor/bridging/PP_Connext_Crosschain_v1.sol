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
    function executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal returns (bytes memory) {
        //@notice call the connextBridgeLogic to execute the bridge transfer
        bytes32 intentId = connextBridgeLogic.xcall(order, executionData);
        return abi.encode(intentId);
    }
}

// this is equivalent ot the forumal
