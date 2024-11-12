// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// External Dependencies
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/bridging/PP_Connext_Crosschain_v1.sol";
import {ConnextBridgeLogic} from
    "src/modules/paymentProcessor/bridging/ConnextBridgeLogic.sol";
import {CrosschainBase_v1} from "src/templates/modules/CrosschainBase_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

// Tests and Mocks
import {Mock_EverclearPayment} from
    "src/templates/tests/unit/mocks/Mock_EverclearPayment.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_Connext_Crosschain_v1_Test is ModuleTest {
    PP_Connext_Crosschain_v1 public processor;
    ConnextBridgeLogic public bridgeLogic;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20Mock public token;
    ERC20PaymentClientBaseV1Mock paymentClient;
    CrosschainBase_v1 public paymentProcessor;

    // Test addresses
    address public recipient = address(0x123);
    uint public constant CHAIN_ID = 1;

    function setUp() public {
        // Deploy token
        token = new ERC20Mock("Test Token", "TEST");

        // Deploy and setup mock payment client
        everclearPaymentMock = new Mock_EverclearPayment();

        address impl = address(new CrosschainBase_v1());
        paymentProcessor = CrosschainBase_v1(Clones.clone(impl));

        //Setup the module to test
        _setUpOrchestrator(paymentProcessor);

        //General setup for other contracts in the workflow
        _authorizer.setIsAuthorized(address(this), true);

        //Initiate the PP with the medata and config data
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));

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

        // Deploy bridge logic and processor
        bridgeLogic = new ConnextBridgeLogic(
            address(everclearPaymentMock), address(token)
        );
        processor = new PP_Connext_Crosschain_v1(CHAIN_ID, address(bridgeLogic));
<<<<<<< HEAD
        paymentClient.setIsAuthorized(address(processor), true);
=======
>>>>>>> 3ef9ac0 (add unit tests for Connext)

        // Setup token approvals and initial balances
        token.mint(address(this), 1000 ether);
        token.approve(address(processor), type(uint).max);
<<<<<<< HEAD
        token.approve(address(bridgeLogic), type(uint).max);

        // Add these lines to ensure proper token flow
        token.mint(address(processor), 1000 ether); // Mint tokens to processor
        vm.prank(address(processor));
        token.approve(address(bridgeLogic), type(uint).max); // Processor approves bridge logic
=======
>>>>>>> 3ef9ac0 (add unit tests for Connext)

        // Setup mock payment orders that will be returned by the mock
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v1.PaymentOrder[](1);
        orders[0] = IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: recipient,
            paymentToken: address(token),
            amount: 100 ether,
            start: block.timestamp,
            cliff: 0,
            end: block.timestamp + 1 days
        });
        paymentClient.addPaymentOrders(orders);
    }

    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    function test_ProcessPayments() public {
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        processor.processPayments(client);
    }
}
