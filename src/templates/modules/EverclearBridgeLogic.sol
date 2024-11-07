// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IPaymentProcessor_v1,
    IERC20PaymentClientBase_v1
} from "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IEverclearSpoke} from
    "src/templates/tests/unit/Interfaces/IEverClearSpoke.sol";

contract EverclearBridgeLogic {
    address public immutable everclearSpoke;
    address public immutable weth;

    constructor(address _everclearSpoke, address _weth) {
        everclearSpoke = _everclearSpoke;
        weth = _weth;
    }

    function bridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        uint32[] memory destinations,
        address recipient,
        address inputAsset,
        uint48 maxFee,
        uint48 ttl
    ) external payable {
        // Call newIntent on the EverClearSpoke contract
        (bytes32 intentId,) = IEverclearSpoke(everclearSpoke).newIntent(
            destinations,
            order.recipient, // to
            address(weth), // order.inputAsset, // inputAsset
            address(weth), // order.outputAsset, // outputAsset (assuming same asset on destination)
            order.amount, // amount
            uint24(maxFee), // maxFee (cast to uint24)
            uint48(ttl), // ttl (cast to uint48)
            "" // empty data field, modify if needed
        );
    }
}
