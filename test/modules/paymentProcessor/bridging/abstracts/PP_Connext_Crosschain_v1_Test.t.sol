// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

// External Dependencies
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/PP_Connext_Crosschain_v1.sol";

import {CrosschainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrosschainBase_v1.sol";
import {CrosschainBase_v1_Exposed} from
    "test/modules/paymentProcessor/bridging/abstracts/CrosschainBase_v1_Exposed.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";

// Tests and Mocks
import {Mock_EverclearPayment} from
    "test/modules/paymentProcessor/bridging/abstracts/mocks/Mock_EverclearPayment.sol";
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
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";

import "forge-std/console2.sol";

contract PP_Connext_Crosschain_v1_Test is ModuleTest {
    PP_Connext_Crosschain_v1 public crossChainManager;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20Mock public token;
    ERC20PaymentClientBaseV1Mock paymentClient;
    CrosschainBase_v1 public paymentProcessor;

    // Test addresses
    address public recipient = address(0x123);
    uint public chainId;

    // Add this event definition at the contract level
    event PaymentProcessed(
        uint indexed paymentId,
        address recipient,
        address paymentToken,
        uint amount
    );

    // Add these as contract state variables
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    uint maxFee = 0;
    uint ttl = 1;
    bytes executionData;
    bytes invalidExecutionData;

    function setUp() public {
        // Set the chainId
        chainId = block.chainid;

        //Set the execution data
        executionData = abi.encode(maxFee, ttl);
        invalidExecutionData = abi.encode(address(0));
        // Deploy token
        token = new ERC20Mock("Test Token", "TEST");

        // Deploy and setup mock payment client
        everclearPaymentMock = new Mock_EverclearPayment();

        address impl = address(new CrosschainBase_v1_Exposed(block.chainid));
        paymentProcessor = CrosschainBase_v1_Exposed(Clones.clone(impl));

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
        paymentClient.setToken(token);
        impl = address(new PP_Connext_Crosschain_v1());
        crossChainManager = PP_Connext_Crosschain_v1(Clones.clone(impl));
        // Setup mock addresses
        mockConnextBridge = address(0x123456);
        mockEverClearSpoke = address(everclearPaymentMock); // Using the existing mock
        mockWeth = address(0x789012); // Or deploy a mock WETH contract if needed

        //init the processor
        // Initialize with proper config data
        bytes memory configData = abi.encode(
            address(mockEverClearSpoke), // address of your EverClear spoke contract
            address(mockWeth) // address of your WETH contract
        );

        crossChainManager.init(_orchestrator, _METADATA, configData);
        paymentClient.setIsAuthorized(address(crossChainManager), true);

        // Setup token approvals and initial balances
        token.mint(address(this), 1000 ether);
        token.approve(address(crossChainManager), type(uint).max);

        // Add these lines to ensure proper token flow
        token.mint(address(crossChainManager), 1000 ether); // Mint tokens to processor
        vm.prank(address(crossChainManager));
        token.approve(address(crossChainManager), type(uint).max); // Processor approves bridge logic
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

    function test_ProcessPayments_singlePayment() public {
        _setupSinglePayment(recipient, 100 ether);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(
            0, // paymentId
            recipient,
            address(token),
            100 ether
        );

        // Process payments
        crossChainManager.processPayments(client, executionData);
    }

    function test_ProcessPayments_multiplePayment() public {
        // Setup mock payment orders that will be returned by the mock
        address[] memory setupRecipients = new address[](3);
        setupRecipients[0] = address(0x1);
        setupRecipients[1] = address(0x2);
        setupRecipients[2] = address(0x3);
        uint[] memory setupAmounts = new uint[](3);
        setupAmounts[0] = 100 ether;
        setupAmounts[1] = 125 ether;
        setupAmounts[2] = 150 ether;
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(3, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments and verify _bridgeData mapping is updated for each paymentId
        // Expect the event
        for (uint i = 0; i < setupRecipients.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit PaymentProcessed(
                i, // paymentId
                setupRecipients[i],
                address(token),
                setupAmounts[i]
            );
        }
        crossChainManager.processPayments(client, executionData);
    }

    function test_ProcessPayments_noPayments() public {
        // Process payments and verify _bridgeData mapping is not updated
        crossChainManager.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
        assertTrue(
            keccak256(crossChainManager.getBridgeData(0))
                == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    function test_ProcessPayments_invalidExecutionData() public {
        // Setup mock payment orders that will be returned by the mock
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = 100 ether;
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert();
        crossChainManager.processPayments(client, invalidExecutionData);
    }

    function test_returnsCorrectBridgeDataRevert() public {
        // Setup mock payment orders that will be returned by the mock
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = 100 ether;
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert();
        crossChainManager.processPayments(client, invalidExecutionData);
    }

    function test_ProcessPayments_emptyExecutionData() public {
        _setupSinglePayment(recipient, 100 ether);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert(
            ICrossChainBase_v1
                .Module__CrossChainBase_InvalidExecutionData
                .selector
        );
        crossChainManager.processPayments(client, bytes(""));
    }

    function test_ProcessPayments_invalidRecipient() public {
        _setupSinglePayment(address(0), 100 ether);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert(
            ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient.selector
        );
        crossChainManager.processPayments(client, executionData);
    }

    function test_ProcessPayments_invalidAmount() public {
        _setupSinglePayment(recipient, 0);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert(
            ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount.selector
        );
        crossChainManager.processPayments(client, executionData);
    }

    function test_returnsCorrectBridgeData() public {
        _setupSinglePayment(recipient, 100 ether);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        crossChainManager.processPayments(client, executionData);
        assertTrue(
            keccak256(crossChainManager.getBridgeData(0))
                != keccak256(bytes("")),
            "Bridge data should not be empty"
        );
    }

    function test_returnsEmptyBridgeData() public {
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        crossChainManager.processPayments(client, executionData);
        assertTrue(
            keccak256(crossChainManager.getBridgeData(0))
                == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    function test_ProcessPayments_InsufficientBalance() public {
        _setupSinglePayment(recipient, 2000 ether);
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                token.balanceOf(address(crossChainManager)),
                2000 ether
            )
        );
        crossChainManager.processPayments(client, executionData);
    }

    //@zuhaib - let's add some tests for unhappy paths here
    // testMaxFeeTooHigh()
    // testInvalidTt()
    // testInvavil
    // Validate that these fuzz tests I wrote are actually helpful they may be redundant

    function testFuzz_ProcessPayments_SinglePayment(
        address fuzzRecipient,
        uint96 amount // Using uint96 to avoid overflow issues
    ) public {
        // Assumptions
        vm.assume(fuzzRecipient != address(0));
        vm.assume(amount > 0 && amount < 1000 ether); // Keeping within our minted balance

        // Setup
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = fuzzRecipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = amount;

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        // Expectations
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(0, fuzzRecipient, address(token), amount);

        // Action
        crossChainManager.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
    }

    function testFuzz_ProcessPayments_MultiplePayments(
        uint8 numPayments, // Using uint8 to keep the number of payments reasonable
        uint96 baseAmount // Base amount that will be varied for each payment
    ) public {
        // Assumptions
        vm.assume(numPayments > 0 && numPayments <= 10); // Limiting max payments
        vm.assume(baseAmount > 0 && baseAmount < 100 ether); // Ensuring total won't exceed balance

        // Setup
        address[] memory setupRecipients = new address[](numPayments);
        uint[] memory setupAmounts = new uint[](numPayments);

        for (uint i = 0; i < numPayments; i++) {
            setupRecipients[i] = address(uint160(i + 1)); // Creating unique addresses
            setupAmounts[i] = baseAmount + (i * 1 ether); // Varying amounts
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(numPayments, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        // Expectations
        for (uint i = 0; i < numPayments; i++) {
            vm.expectEmit(true, true, true, true);
            emit PaymentProcessed(
                i, setupRecipients[i], address(token), setupAmounts[i]
            );
        }

        // Action
        crossChainManager.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
    }

    function testFuzz_ProcessPayments_EdgeCaseAmounts(uint96 amount) public {
        // Assumptions
        vm.assume(amount > 0 && amount <= 1000 ether);
        vm.assume(recipient != address(0));

        // Setup - Clear existing balance
        uint currentBalance = token.balanceOf(address(crossChainManager));
        if (currentBalance > 0) {
            vm.prank(address(crossChainManager));
            token.transfer(address(1), currentBalance);
        }

        // Setup - Mint exact amount needed
        token.mint(address(crossChainManager), amount);

        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = amount;

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        // Expectations
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(0, recipient, address(token), amount);

        // Action
        crossChainManager.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
    }

    // Helper functions

    function _setupSinglePayment(address _recipient, uint _amount) internal {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = _recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = _amount;

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);
    }

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
                paymentToken: address(token),
                amount: amounts[i],
                start: block.timestamp,
                cliff: 0,
                end: block.timestamp + 1 days
            });
        }
        return orders;
    }
}
