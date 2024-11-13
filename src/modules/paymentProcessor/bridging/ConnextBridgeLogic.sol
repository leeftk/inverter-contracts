// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/bridging/abstracts/CrosschainBase_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

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

contract ConnextBridgeLogic {
    IEverclearSpoke public everClearSpoke;
    address public immutable weth;

    constructor(address _everclearSpoke, address _weth) {
        everClearSpoke = IEverclearSpoke(_everclearSpoke);
        weth = _weth;
    }

    function xcall(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external payable returns (bytes32 intentId) {
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
