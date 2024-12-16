// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies

// External Dependencies
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface ICrossChain_Base_v1 {
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
    event BridgeTransferExecuted(
        uint indexed paymentId,
        bytes indexed bridgeData
    );

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
    // Public (Getter)

    /// @notice Get the chain ID
    /// @return The chain ID
    function getChainId() external view returns (uint);

}
