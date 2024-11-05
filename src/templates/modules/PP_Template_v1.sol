// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IPaymentProcessor_v1} from "@pp/IPaymentProcessor_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IPP_CrossChain_v1} from "./IPP_Template_v1.sol";
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";

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
abstract contract PP_CrossChain_v1 is
    IPP_CrossChain_v1,
    IPaymentProcessor_v1,
    Module_v1
{
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId_)
        public
        view
        virtual
        override(Module_v1)
        returns (bool)
    {
        return interfaceId_ == type(IPP_CrossChain_v1).interfaceId
            || interfaceId_ == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId_);
    }
    //--------------------------------------------------------------------------
    // State

    /// @dev Mapping of payment ID to bridge transfer return data
    mapping(uint => bytes) internal _bridgeData;

    bytes public executionData;

    /// @dev    Payout amount multiplier.
    uint internal _payoutAmountMultiplier;

    /// @dev    The number of payment orders.
    uint internal _paymentId;

    //--------------------------------------------------------------------------
    // Events

    event PaymentProcessed(
        uint indexed paymentId, address recipient, address token, uint amount
    );

    /// @dev    Checks that the client is calling for itself.
    modifier validClient(address client_) {
        // modifier logic moved to internal function for contract size reduction
        _validClientModifier(client_);
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    function processPayments(IERC20PaymentClientBase_v1 client_)
        external
        virtual
        validClient(address(client_))
    {
        // Collect orders from the client
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders;
        (orders,,) = client_.collectPaymentOrders();

        for (uint i = 0; i < orders.length; i++) {
            bytes memory bridgeData =
                this._executeBridgeTransfer(orders[i], executionData);
            _bridgeData[_paymentId] = bridgeData;

            emit PaymentProcessed(
                _paymentId,
                orders[i].recipient,
                orders[i].paymentToken,
                orders[i].amount
            );
            _paymentId++;

            // Inform the client about the processed amount
            client_.amountPaid(orders[i].paymentToken, orders[i].amount);
        }
    }

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client_)
        external
        view
        virtual
        validClient(address(client_))
    {
        // This function is used to implement custom logic to cancel running payments. If the nature of
        // processing payments is one of direct processing then this function can be left empty, return nothing.
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(
        address, /*client_*/
        address, /*token_*/
        address /*paymentReceiver_*/
    ) external view virtual returns (uint amount_) {
        // This function is used to check if there are unclaimable tokens for a specific client, token and payment
        // receiver. As this template only executes one payment order at a time, this function is not utilzed and can
        // return 0.
        return 0;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function claimPreviouslyUnclaimable(
        address, /*client_*/
        address, /*token_*/
        address /*receiver_*/
    ) external virtual {
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order_
    ) external virtual returns (bool) {
        // This function is used to validate the payment order created on the client side (LM) with the input required by the
        // Payment Processor (PP). The function should return true if the payment order is valid and false if it is not.

        // For this template, only the receiver is validated.
        return _validPaymentReceiver(order_.recipient);
    }

    //--------------------------------------------------------------------------
    // Internal

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Internal function to set the new payout amount multiplier.
    /// @param newPayoutAmountMultiplier_ Payout amount multiplier to be set in the state. Cannot be zero.
    function _setPayoutAmountMultiplier(uint newPayoutAmountMultiplier_)
        internal
    {
        if (newPayoutAmountMultiplier_ == 0) {
            revert Module__PP_Template_InvalidAmount();
        }
        emit NewPayoutAmountMultiplierSet(
            _payoutAmountMultiplier, newPayoutAmountMultiplier_
        );
        _payoutAmountMultiplier = newPayoutAmountMultiplier_;
    }

    /// @dev    Validate address input.
    /// @param  addr_ Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr_)
        internal
        view
        virtual
        returns (bool)
    {
        return !(
            addr_ == address(0) || addr_ == _msgSender()
                || addr_ == address(this) || addr_ == address(orchestrator())
                || addr_ == address(orchestrator().fundingManager().token())
        );
    }

    function _validClientModifier(address client_) internal view {
        if (_msgSender() != client_) {
            revert Module__PP_Template__NotValidClient();
        }
    }

    //--------------------------------------------------------------------------
    // Virtual Functions

    /// @notice Execute the cross-chain bridge transfer
    /// @dev Override this function to implement specific bridge logic
    /// @param order The payment order containing all necessary transfer details
    /// @return bridgeData Arbitrary data returned by the bridge implementation
    function _executeBridgeTransfer(
        IERC20PaymentClientBase_v1.PaymentOrder memory order,
        bytes memory executionData
    ) public virtual returns (bytes memory) {
        return bytes("");
    }
}

//// payment process module ---> exposing internal function

//// build bridge mock
