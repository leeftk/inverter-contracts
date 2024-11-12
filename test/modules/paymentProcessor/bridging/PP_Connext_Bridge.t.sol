//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from "src/templates/modules/ICrosschainBase_v1.sol";
import {CrosschainBase_v1} from "src/templates/modules/CrosschainBase_v1.sol";
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
import {PP_CrossChain_v1_Exposed} from
    "../../tests/unit/PP_CrossChain_v1_Exposed.sol";

//System under test (SuT)
import {
    PP_Connext_Crosschain_v1,
    IPP_Connext_Crosschain_v1
} from "../../../src/templates/modules/Connext_Bridge.sol";
import {IPaymentProcessor_v1} from
    "../../../src/orchestrator/interfaces/IOrchestrator_v1.sol";

import {ICrossChainBase_v1} from "src/templates/modules/ICrosschainBase_v1.sol";
import {console2} from "forge-std/console2.sol";
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

contract PP_Connext_Bridge_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    uint internal constant _payoutAmountMultiplier = 2;

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
        address impl = address(new CrosschainBase_v1());
        paymentProcessor = CrosschainBase_v1(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(paymentProcessor);

        //General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        //Initiate the PP with the medata and config data
        paymentProcessor.init(
            _orchestrator, _METADATA, abi.encode(_payoutAmountMultiplier)
        );

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
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    //Test the interface support
    function testSupportsInterface() public {
        assertTrue(
            paymentProcessor.supportsInterface(
                type(ICrossChainBase_v1).interfaceId
            )
        );
    }

    //Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(
            _orchestrator, _METADATA, abi.encode(_payoutAmountMultiplier)
        );
    }
}
