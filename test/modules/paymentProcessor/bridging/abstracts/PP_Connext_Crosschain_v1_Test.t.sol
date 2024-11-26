// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

// External Dependencies
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";

// Internal Dependencies
import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/PP_Connext_Crosschain_v1.sol";

import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {CrossChainBase_v1_Exposed} from
    "test/modules/paymentProcessor/bridging/abstracts/CrossChainBase_v1_Exposed.sol";
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
    CrossChainBase_v1 public paymentProcessor;

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
    uint ttl = 0;
    bytes executionData;
    bytes invalidExecutionData;

    uint constant MINTED_SUPPLY = 1000 ether;

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

        address impl = address(new CrossChainBase_v1_Exposed(block.chainid));
        paymentProcessor = CrossChainBase_v1_Exposed(Clones.clone(impl));

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

        // Call the new function for balances setup
        _setupInitialBalances();
    }

    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    function testSupportsInterface() public {
        // Test for IModule_v1 interface
        assertTrue(
            crossChainManager.supportsInterface(type(IModule_v1).interfaceId)
        );

        // Test for ICrossChainBase_v1 interface
        assertTrue(
            crossChainManager.supportsInterface(
                type(ICrossChainBase_v1).interfaceId
            )
        );

        // Test for a non-supported interface (using a random interface ID)
        assertFalse(crossChainManager.supportsInterface(0xffffffff));
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    function testFuzz_ProcessPayments_singlePayment(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(testRecipient, testAmount);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Expect the event
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(
            0, // paymentId
            testRecipient,
            address(token),
            testAmount
        );

        // Process payments
        crossChainManager.processPayments(client, executionData);
    }

    function testFuzz_ProcessPayments_multiplePayment(
        uint8 numRecipients,
        address testRecipient,
        uint96 baseAmount
    ) public {
        // Assumptions to keep the test manageable and within bounds
        vm.assume(numRecipients > 0 && numRecipients <= type(uint8).max); // Limit array size
        vm.assume(testRecipient != address(0));
        vm.assume(baseAmount > 0 && baseAmount <= MINTED_SUPPLY / numRecipients); // Ensure total amount won't exceed MINTED_SUPPLY

        // Setup mock payment orders
        address[] memory setupRecipients = new address[](numRecipients);
        uint[] memory setupAmounts = new uint[](numRecipients);

        for (uint i = 0; i < numRecipients; i++) {
            setupRecipients[i] = testRecipient;
            setupAmounts[i] =
                1 + (uint(keccak256(abi.encode(i, baseAmount))) % baseAmount);
        }

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(numRecipients, setupRecipients, setupAmounts);
        paymentClient.addPaymentOrders(orders);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Expect events for each payment
        for (uint i = 0; i < numRecipients; i++) {
            vm.expectEmit(true, true, true, true);
            emit PaymentProcessed(
                i, // paymentId
                setupRecipients[i],
                address(token),
                setupAmounts[i]
            );
        }

        // Process payments
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

    function testFuzz_ProcessPayments_invalidExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(testRecipient, testAmount);

        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert();
        crossChainManager.processPayments(client, invalidExecutionData);
    }

    function testFuzz_returnsCorrectBridgeDataRevert(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance
        _setupSinglePayment(testRecipient, testAmount);

        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert();
        crossChainManager.processPayments(client, invalidExecutionData);
    }

    function testFuzz_ProcessPayments_emptyExecutionData(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(testRecipient, testAmount);

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

    function testFuzz_ProcessPayments_invalidRecipient(uint testAmount)
        public
    {
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(address(0), testAmount);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert(
            ICrossChainBase_v1.Module__CrossChainBase__InvalidRecipient.selector
        );
        crossChainManager.processPayments(client, executionData);
    }

    function testFuzz_ProcessPayments_invalidAmount(address testRecipient)
        public
    {
        vm.assume(testRecipient != address(0));

        _setupSinglePayment(testRecipient, 0);
        // Get the client interface
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        // Process payments
        vm.expectRevert(
            ICrossChainBase_v1.Module__CrossChainBase__InvalidAmount.selector
        );
        crossChainManager.processPayments(client, executionData);
    }

    function testFuzz_returnsCorrectBridgeData(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY); // Keeping within our minted balance

        _setupSinglePayment(testRecipient, testAmount);
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

        bytes32 intentId = bytes32(crossChainManager.getBridgeData(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
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

    function testFuzz_ProcessPayments_InsufficientBalance(
        address testRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(testAmount > MINTED_SUPPLY && testAmount <= type(uint96).max);

        _setupSinglePayment(testRecipient, testAmount);
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                token.balanceOf(address(crossChainManager)),
                testAmount
            )
        );
        crossChainManager.processPayments(client, executionData);
    }

    //@zuhaib - let's add some tests for unhappy paths here
    // testMaxFeeTooHigh()
    // testInvalidTt()
    // testInvavil @33audits - in case of everclear, both maxFee and ttl can be zero, please check https://docs.everclear.org/developers/guides/xerc20#newintent-called-on-spoke-contract
    // Validate that these fuzz tests I wrote are actually helpful they may be redundant

    function testFuzz_ProcessPayments_EdgeCaseAmounts(
        address testRecipient,
        uint96 testAmount
    ) public {
        vm.assume(testAmount > 0 && testAmount <= MINTED_SUPPLY);
        // Assumption
        vm.assume(testRecipient != address(0));

        // Setup - Clear existing balance
        uint currentBalance = token.balanceOf(address(crossChainManager));
        if (currentBalance > 0) {
            vm.prank(address(crossChainManager));
            token.transfer(address(1), currentBalance);
        }

        // Setup - Mint exact amount needed
        token.mint(address(crossChainManager), testAmount);

        _setupSinglePayment(testRecipient, testAmount);

        // Expectations
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(0, testRecipient, address(token), testAmount);

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

    function _setupInitialBalances() internal {
        // Setup token approvals and initial balances
        token.mint(address(this), MINTED_SUPPLY);
        token.approve(address(crossChainManager), type(uint).max);

        token.mint(address(crossChainManager), MINTED_SUPPLY); // Mint tokens to processor
        vm.prank(address(crossChainManager));
        token.approve(address(crossChainManager), type(uint).max); // Processor approves bridge logic
    }
}
