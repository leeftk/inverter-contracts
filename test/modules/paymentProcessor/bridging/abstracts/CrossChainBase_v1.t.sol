//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
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
import {CrossChainBase_v1_Exposed} from "./CrossChainBase_v1_Exposed.sol";

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
import {OZErrors} from "test/utils/errors/OZErrors.sol";

/**
 * @title   CrossChainBase Test Suite
 *
 * @notice  Test suite for the CrossChainBase_v1 abstract contract
 *
 * @dev     Tests the core functionality of the CrossChainBase contract including:
 *          - Contract initialization and reinitialization protection
 *          - Interface support verification
 *          - Bridge transfer execution
 *          - Integration with the Inverter workflow through ModuleTest
 *
 * @custom:security-contact security@inverter.network
 *                          In case of any concerns or findings, please refer to our Security Policy
 *                          at security.inverter.network or email us directly!
 *
 * @author  Inverter Network
 */
contract CrossChainBase_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    //Constants
    //--------------------------------------------------------------------------
    //Mocks
    ERC20PaymentClientBaseV1Mock paymentClient;
    CrossChainBase_v1_Exposed public crossChainBase;

    //--------------------------------------------------------------------------
    //Setup
    function setUp() public {
        //This function is used to setup the unit test
        //Deploy the SuT
        address impl = address(new CrossChainBase_v1_Exposed(block.chainid));
        crossChainBase = CrossChainBase_v1_Exposed(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(crossChainBase);

        //General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        //Initiate the PP with the medata and config data
        crossChainBase.init(_orchestrator, _METADATA, abi.encode(1));

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
        paymentClient.setIsAuthorized(address(crossChainBase), true);
        paymentClient.setToken(_token);
    }
    /* Test CrossChainBase functionality
        ├── Given the contract is initialized
        │   └── When checking interface support
        │       └── Then it should support ICrossChainBase_v1
        │       └── Then it should not support random interfaces
        ├── Given the contract is already initialized
        │   └── When trying to reinitialize
        │       └── Then it should revert
        └── Given a valid payment order
            └── When executeBridgeTransfer is called
                └── Then it should return empty bytes
    */

    //--------------------------------------------------------------------------
    //Test: Initialization
    function testInit() public override(ModuleTest) {
        assertEq(address(crossChainBase.orchestrator()), address(_orchestrator));
    }

    //--------------------------------------------------------------------------
    //Test: Interface Support
    function testSupportsInterface() public {
        // Test for ICrossChainBase_v1 interface support
        bytes4 interfaceId = type(ICrossChainBase_v1).interfaceId;
        assertTrue(crossChainBase.supportsInterface(interfaceId));

        // Test for random interface ID (should return false)
        bytes4 randomInterfaceId = bytes4(keccak256("random()"));
        assertFalse(crossChainBase.supportsInterface(randomInterfaceId));
    }

    //Test the reinit function
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        crossChainBase.init(_orchestrator, _METADATA, abi.encode(1));
    }
    //--------------------------------------------------------------------------
    //Test: executeBridgeTransfer

    function testExecuteBridgeTransfer() public {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = address(1);
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = 100 ether;

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        bytes memory executionData = abi.encode(0, 0); //maxFee and ttl setup

        bytes memory result = crossChainBase.exposed_executeBridgeTransfer(
            orders[0], executionData
        );
        assertEq(result, bytes(""));
    }
    //--------------------------------------------------------------------------
    //Helper Functions

    function _createPaymentOrders(
        uint orderCount,
        address[] memory recipients,
        uint[] memory amounts
    )
        internal
        view
        returns (IERC20PaymentClientBase_v1.PaymentOrder[] memory)
    {
        // Sanity checks for array lengths
        require(
            recipients.length == orderCount && amounts.length == orderCount,
            "Array lengths must match orderCount"
        );
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v1.PaymentOrder[](orderCount);
        for (uint i = 0; i < orderCount; i++) {
            orders[i] = IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipients[i],
                paymentToken: address(0xabcd),
                amount: amounts[i],
                start: block.timestamp,
                cliff: 0,
                end: block.timestamp + 1 days
            });
        }
        return orders;
    }
}
