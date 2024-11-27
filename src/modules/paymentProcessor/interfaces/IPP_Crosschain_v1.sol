// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";

/// @notice Interface for cross-chain payment processing functionality
interface IPP_Crosschain_v1 is IPaymentProcessor_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Thrown when the cross-chain message fails to be delivered
    /// @param sourceChain The chain ID where the message originated
    /// @param destinationChain The chain ID where the message was meant to be delivered
    /// @param executionData The encoded execution parameters (maxFee, ttl)
    error Module__PP_Crosschain__MessageDeliveryFailed(
        uint sourceChain, uint destinationChain, bytes executionData
    );

    /// @notice Thrown when attempting to process a cross-chain payment with invalid parameters
    /// @param paymentClient The address of the payment client
    /// @param paymentId The ID of the payment being processed
    /// @param destinationChain The target chain ID for the payment
    error Module__PP_Crosschain__InvalidPaymentParameters(
        address paymentClient, uint paymentId, uint destinationChain
    );

    /// @notice Thrown when the cross-chain bridge fees exceed the maximum allowed
    error Module__PP_Crosschain__InvalidBridgeFee();
}
