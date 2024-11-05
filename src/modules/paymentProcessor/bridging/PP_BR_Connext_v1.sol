// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {
    IPaymentProcessor_v1,
    IERC20PaymentClientBase_v1
} from "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {PP_CrossChain_v1} from "src/templates/modules/PP_Template_v1.sol";

// Internal Dependencies
import {ERC165Upgradeable, Module_v1} from "src/modules/base/Module_v1.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Inverter Simple Payment Processor
 *
 * @notice  Manages ERC20 payment processing for modules within the Inverter Network
 *          that are compliant with the {IERC20PaymentClientBase_v1} interface.
 *
 * @dev     Inherits {Module_v1} and implements {IPaymentProcessor_v1} to handle payment
 *          orders from registered modules, ensuring only eligible modules can initiate
 *          payments. Utilizes {SafeERC20} for secure token transfers.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */

//TODO: Here's my guess of how we should do next
// - Inherit from the PP_Template_v1 base and maybe even the interface too?
// - Implement the internal execute bridge function in here, aka wrap it with an external function and leave space for logic
// - Add the logic from Everclear contract to the executeBridge fucntion (or connext if that's easier since we're mocking it for now)
// - Make sure it compiles and the if you have time write a test file that copiles
// - Test file can be in this same folder with the same nameing convention as PP_Template_v1_.t.sol, except for the name I choose here
// - Feel free to copy pp_template_v1.t.sol setup and helper fucntions to get started
// - Make sure this compiles
// - We then need to create mocks that will mock a call to the bridge
// - This is straightforward, just check to see what event the connext bridge emits after deposit
// - Create a function with the same selector in the mock, when the proper params are passed it should emit the event
// - We then need to write some basic testcases that will test the bridge logic, this should be mocked
contract PP_BR_Connext_v1 is
    PP_CrossChain_v1 //@note -> PP_CrossChain_v1 already inherits from Module_v1 and IPaymentProcessor_v1
{
    //Module_v1,
    //IPaymentProcessor_v1
    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(PP_CrossChain_v1)
        returns (bool)
    {
        return interfaceId == type(IPaymentProcessor_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Modifiers

    /// @dev    Checks that the caller is an active module.
    modifier onlyModule() {
        if (!orchestrator().isModule(_msgSender())) {
            revert Module__PaymentProcessor__OnlyCallableByModule();
        }
        _;
    }

    // /// @dev    Checks that the client is calling for itself.
    // modifier validClient(address client) {
    //     if (_msgSender() != client) {
    //         revert Module__PaymentProcessor__CannotCallOnOtherClientsOrders();
    //     }
    //     _;
    // }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev    Tracks all payments that could not be made to the paymentReceiver due to any reason.
    /// @dev	paymentClient => token address => paymentReceiver => unclaimable Amount.
    mapping(address => mapping(address => mapping(address => uint))) internal
        unclaimableAmountsForRecipient;

    /// @dev    Gap for possible future upgrades.
    uint[50] private __gap;

    //--------------------------------------------------------------------------
    // Initializer

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory /*configData*/
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);
    }

    //--------------------------------------------------------------------------
    // IPaymentProcessor_v1 Functions

    /// @inheritdoc IPaymentProcessor_v1
    function processPayments(IERC20PaymentClientBase_v1 client)
        external
        override(PP_CrossChain_v1)
        onlyModule
        validClient(address(client))
    {}

    /// @inheritdoc IPaymentProcessor_v1
    function cancelRunningPayments(IERC20PaymentClientBase_v1 client)
        external
        view
        override
        onlyModule
        validClient(address(client))
    {
        // Since we pay out on processing, this function does nothing
        return;
    }

    /// @inheritdoc IPaymentProcessor_v1
    function unclaimable(address client, address token, address paymentReceiver)
        public
        view
        override
        returns (uint amount)
    {
        return unclaimableAmountsForRecipient[client][token][paymentReceiver];
    }

    // /// @inheritdoc IPaymentProcessor_v1
    // function claimPreviouslyUnclaimable(
    //     address client,
    //     address token,
    //     address receiver
    // ) external override {
    //     if (unclaimable(client, token, _msgSender()) == 0) {
    //         revert Module__PaymentProcessor__NothingToClaim(
    //             client, _msgSender()
    //         );
    //     }

    //     _claimPreviouslyUnclaimable(client, token, receiver);
    // }

    /// @inheritdoc IPaymentProcessor_v1
    function validPaymentOrder(
        IERC20PaymentClientBase_v1.PaymentOrder memory order
    ) external view override returns (bool) {
        return
            _validPaymentReceiver(order.recipient) && _validTotal(order.amount); //&& _validPaymentToken(order.paymentToken);
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @notice used to claim the unclaimable amount of a particular `paymentReceiver` for a given payment client.
    /// @param  client address of the payment client.
    /// @param  token address of the payment token.
    /// @param  paymentReceiver address of the paymentReceiver for which the unclaimable amount will be claimed.
    function _claimPreviouslyUnclaimable(
        address client,
        address token,
        address paymentReceiver
    ) internal {
        // get amount

        address sender = _msgSender();
        // copy value over
        uint amount = unclaimableAmountsForRecipient[client][token][sender];
        // Delete the field
        delete unclaimableAmountsForRecipient[client][token][sender];

        // Make sure to let paymentClient know that amount doesnt have to be stored anymore
        IERC20PaymentClientBase_v1(client).amountPaid(token, amount);

        // Call has to succeed otherwise no state change
        IERC20(token).safeTransferFrom(client, paymentReceiver, amount);

        emit TokensReleased(paymentReceiver, address(token), amount);
    }

    /// @notice Validate address input.
    /// @param  addr Address to validate.
    /// @return True if address is valid.
    function _validPaymentReceiver(address addr)
        internal
        view
        override
        returns (bool)
    {
        return !(
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(orchestrator())
                || addr == address(orchestrator().fundingManager().token())
        );
    }

    /// @notice Validate uint total amount input.
    /// @param  _total uint to validate.
    /// @return True if uint is valid.
    function _validTotal(uint _total) internal pure returns (bool) {
        return !(_total == 0);
    }

    /// @notice Validate payment token input.
    /// @param  _token Address of the token to validate.
    /// @return True if address is valid.
    function _validPaymentToken(address _token) internal returns (bool) {
        // Only a basic sanity check that the address supports the balanceOf() function. The corresponding
        // module should ensure it's sending an ERC20.

        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20(_token).balanceOf.selector, address(this)
            )
        );
        return (success && data.length != 0 && _token.code.length != 0);
    }
}
