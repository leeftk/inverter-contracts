//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrosschainBase_v1.sol";
//External Dependencies
import {Clones} from "@oz/proxy/Clones.sol";

//Tests and Mocks
// import cr
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
//import exposed
import {CrosschainBase_v1_Exposed} from "./CrosschainBase_v1_Exposed.sol";

//System under test (SuT)
// import {
//     IPP_CrossChain_v1,
//     PP_CrossChain_v1,
//     IPaymentProcessor_v1
// } from "src/templates/modules/PP_Template_v1.sol";
import {IPaymentProcessor_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";

/**
 * @title   Inverter Template Payment Processor
 *
 * @notice  Basic template payment processor used to showcase the unit testing setup
 *
 * @dev     Not all functions are tested in this template. Placeholders of the functions that are not tested are added
 *          into the contract. This test showcases the following:
 *          - Inherit from the ModuleTest contract to enable interaction with the Inverter workflow.
 *          - Showcases the setup of the workflow, uses in test unit tests.
 *          - Pre-defined layout for all setup and functions to be tested.
 *          - Shows the use of Gherkin for documenting the testing. VS Code extension used for formatting is recommended.
 *          - Shows the use of the modifierInPlace pattern to test the modifier placement.
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract CrosschainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    //--------------------------------------------------------------------------
    //State

    //Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;

    //System under test (SuT)
    CrosschainBase_v1 public paymentProcessor;
    //PP_CrossChain_v1_Exposed public paymentProcessor;

    //--------------------------------------------------------------------------
    //Setup
    function setUp() public {
        //This function is used to setup the unit test
        //Deploy the SuT
        address impl = address(new CrosschainBase_v1_Exposed(block.chainid));
        paymentProcessor = CrosschainBase_v1(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(paymentProcessor);

        //General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        //Setup other modules needed in the unit tests.
        //In this case a payment client is needed to test the PP_Template_v1.
        impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));
        //Adding the payment client is done through a timelock mechanism
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));
        //Init payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);
    }

    //--------------------------------------------------------------------------
    //Test: Initialization

    //Test if the orchestrator is correctly set
    function testInit() public override(ModuleTest) {}

    //Test the interface support
    function testSupportsInterface() public {}

    //Test the reinit function
    function testReinitFails() public override(ModuleTest) {}
    // -----ALL below this we're keeping for reference, but not testing
    //--------------------------------------------------------------------------
    //Test: Modifiers

    /* Test validClient modifier in place (extensive testing done through internal modifier functions)
        └── Given the modifier is in place
            └── When the function processPayment() is called
                └── Then it should revert
    */
    // function testProcessPayments_modifierInPlace() public {
    // }
    //
    //--------------------------------------------------------------------------
    //Test: External (public & external)Cros

    //Test external processPayments() function

    //Test external cancelRunningPayments() function

    //Test external unclaimable() function

    //Test external claimPreviouslyUnclaimable() function

    //Test external validPaymentOrder() function

    //--------------------------------------------------------------------------
    //Test: Internal (tested through exposed_functions)

    /*  test internal _setPayoutAmountMultiplier()
        ├── Given the newPayoutAmount == 0
        │   └── When the function _setPayoutAmountMultiplier() is called
        │       └── Then it should revert
        └── Given the newPayoutAmount != 0
            └── When the function _setPayoutAmountMultiplier() is called
                └── Then it should emit the event
                    └── And it should set the state correctly
    */

    //function testInternalSetPayoutAmountMultiplier_FailsGivenZero() public {
    // }

    //Test the internal _validPaymentReceiver() function

    //Test the internal _validClientModifier() function

    //--------------------------------------------------------------------------
    //Helper Functions
}
