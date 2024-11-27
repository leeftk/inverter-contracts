// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {IEverclearSpoke} from
    "src/modules/paymentProcessor/interfaces/IEverclear.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";

interface IPP_Connext_Crosschain_v1 is IPaymentProcessor_v1 {
    /// @notice Returns the Everclear spoke contract instance
    function everClearSpoke() external view returns (IEverclearSpoke);

    /// @notice Returns the WETH contract instance
    function weth() external view returns (IWETH);

    /// @notice Process payments for a given client with execution data
    /// @param client The payment client contract
    /// @param executionData The encoded execution parameters (maxFee, ttl)
    function processPayments(
        IERC20PaymentClientBase_v1 client,
        bytes memory executionData
    ) external;

    /// @notice Get bridge data for a specific payment ID
    /// @param paymentId The ID of the payment
    /// @return The bridge data associated with the payment
    function getBridgeData(uint paymentId)
        external
        view
        returns (bytes memory);
}
