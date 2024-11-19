// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
//import {IPP_CrossChain_v1} from "./IPP_Template_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";
import {ICrossChainBase_v1} from "../interfaces/ICrosschainBase_v1.sol";
/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used as base for developing new payment processors.
 *
 * @dev     This contract is used to showcase a basic setup for a payment processor. The contract showcases the
 *          following:
 *          - Inherit from the Module_v1 contract to enable interaction with the Inverter workflow.
 *          - Use of the IPaymentProcessor_v1 interface to facilitate interaction with a payment client.
 *          - Implement custom interface which has all the public facing functions, errors, events and structs.
 *          - Pre-defined layout for all contract functions, modifiers, state variables etc.
 *          - Use of the ERC165Upgradeable contract to check for interface support.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */

abstract contract CrosschainBase_v1 is ICrossChainBase_v1, Module_v1 {
    mapping(uint => bytes) internal _bridgeData;
    /// @inheritdoc ERC165Upgradeable

    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(ICrossChainBase_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }
    //--------------------------------------------------------------------------
    // State

    /// @dev    The number of payment orders.
    uint internal _paymentId;

    //--------------------------------------------------------------------------
    // Events

    event PaymentProcessed(
        uint indexed paymentId, address recipient, address token, uint amount
    );

    //--------------------------------------------------------------------------
    // Virtual Functions

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) internal virtual returns (bytes memory) {
        emit BridgeTransferExecuted(executionData);
        return bytes("");
    }
    /// @notice Process payments for a given payment client
    /// @param client The payment client to process payments for

    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        virtual
    {}

    /// @notice Get the bridge data for a given payment ID
    /// @param paymentId The ID of the payment to get the bridge data for
    /// @return The bridge data for the given payment ID
    function getBridgeData(uint paymentId)
        external
        view
        returns (bytes memory)
    {
        return _bridgeData[paymentId];
    }
}
