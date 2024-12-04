// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies

// External Dependencies
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface ICrossChainBase_v1 {
    //--------------------------------------------------------------------------
    // Structs

    /// @notice Struct to hold cross-chain message data
    struct CrossChainMessage {
        uint messageId;
        address sourceChain;
        address targetChain;
        bytes payload;
        bool executed;
    }

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a bridge transfer is executed
    event BridgeTransferExecuted(bytes indexed bridgeData);

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__CrossChainBase__InvalidAmount();

    /// @notice Client is not valid.
    error Module__CrossChainBase__NotValidClient();

    /// @notice Message has already been executed
    error Module__CrossChainBase_MessageAlreadyExecuted();

    /// @notice Invalid chain ID provided
    error Module__CrossChainBase_InvalidChainId();

    /// @notice Message verification failed
    error Module__CrossChainBase_MessageVerificationFailed();

    //--------------------------------------------------------------------------
    // Virtual Functions

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external returns (bytes memory);
}
