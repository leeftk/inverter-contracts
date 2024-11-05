// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies

// External Dependencies
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

interface IPP_CrossChain_v1 {
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

    /// @notice Emit when new payout amount has been set.
    /// @param oldPayoutAmount Old payout amount.
    /// @param newPayoutAmount Newly set payout amount.
    event NewPayoutAmountMultiplierSet(
        uint indexed oldPayoutAmount, uint indexed newPayoutAmount
    );

    /// @notice Emitted when a cross-chain message is sent
    /// @param messageId Unique identifier for the message
    /// @param targetChain Address of the target chain
    event CrossChainMessageSent(
        uint indexed messageId, address indexed targetChain
    );

    /// @notice Emitted when a cross-chain message is received
    /// @param messageId Unique identifier for the message
    /// @param sourceChain Address of the source chain
    event CrossChainMessageReceived(
        uint indexed messageId, address indexed sourceChain
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Amount can not be zero.
    error Module__PP_Template_InvalidAmount();

    /// @notice Client is not valid.
    error Module__PP_Template__NotValidClient();

    error Module__PP_CrossChain__NotValidClient();

    error Module__PP_CrossChain__InvalidAmount();

    /// @notice Message has already been executed
    error Module__PP_CrossChain_MessageAlreadyExecuted();
    /// @notice Invalid chain ID provided
    error Module__PP_CrossChain_InvalidChainId();
    /// @notice Message verification failed
    error Module__PP_CrossChain_MessageVerificationFailed();

    //--------------------------------------------------------------------------
    // Public (Getter)

    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) external payable returns (bytes memory); //@note: The error says if declared in interface , it should be external only, need to check this
}
