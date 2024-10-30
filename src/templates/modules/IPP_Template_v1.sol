// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used as base for developing new
 *          payment processors.
 *
 * @dev     This contract is used to showcase a basic setup for a payment
 *          processor. The contract showcases the following:
 *          - Inherit from the Module_v1 contract to enable interaction with
 *            the Inverter workflow.
 *          - Use of the IPaymentProcessor_v1 interface to facilitate
 *            interaction with a payment client.
 *          - Implement custom interface which has all the public facing
 *            functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state
 *            variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface
 *            support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer
 *                          to our Security Policy at security.inverter.network
 *                          or email us directly!
 *
 * @custom:version 1.0.0
 *
 * @author  Inverter Network
 */
interface IPP_Template_v1 is IPaymentProcessor_v1 {
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
    /// @param  oldPayoutAmount_ Old payout amount.
    /// @param  newPayoutAmount_ Newly set payout amount.
    event NewPayoutAmountMultiplierSet(
        uint indexed oldPayoutAmount_, uint indexed newPayoutAmount_
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
    error Module__PP_Template__ClientNotValid();

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

    /// @notice Returns the payout amount for each payment order.
    /// @return payoutAmountMultiplier_ The payout amount multiplier.
    function getPayoutAmountMultiplier()
        external
        returns (uint payoutAmountMultiplier_);

    //--------------------------------------------------------------------------
    // Public (Mutating)
}
