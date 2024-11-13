pragma solidity ^0.8.20;

import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/bridging/abstracts/CrosschainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/bridging/abstracts/ICrosschainBase_v1.sol";
import {ConnextBridgeLogic} from "./ConnextBridgeLogic.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEverclearSpoke {
    function newIntent(
        uint32[] memory destinations,
        address to,
        address inputAsset,
        address outputAsset,
        uint amount,
        uint24 maxFee,
        uint48 ttl,
        bytes memory data
    ) external returns (bytes32 intentId, uint amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract PP_Connext_Crosschain_v1 is CrosschainBase_v1 {
    ConnextBridgeLogic public connextBridgeLogic;
    IEverclearSpoke public everClearSpoke;
    IWETH public weth;

    constructor(address everClearSpoke_, address weth_) {
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

    function xcall(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal returns (bytes32 intentId) {
        // Decode any additional parameters from executionData
        (uint maxFee, uint ttl) = abi.decode(executionData, (uint, uint));

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
        destinations[0] = 8453; // @note -> hardcode for now -> order.destinationChainId;

        // Call newIntent on the EverClearSpoke contract
        (bytes32 intentId,) = everClearSpoke.newIntent(
            destinations,
            order.recipient, // to
            order.paymentToken, // inputAsset
            address(weth), // outputAsset (assuming same asset on destination)
            order.amount, // amount
            uint24(maxFee), // maxFee (cast to uint24)
            uint48(ttl), // ttl (cast to uint48)
            "" // empty data field, modify if needed
        );

        return intentId;
    }
}
