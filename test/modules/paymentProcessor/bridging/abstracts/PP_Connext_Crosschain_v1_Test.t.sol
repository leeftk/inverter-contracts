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
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {PP_Connext_Crosschain_v1_Exposed} from
    "test/modules/paymentProcessor/bridging/abstracts/PP_Connext_Crosschain_v1_Exposed.sol";
// Tests and Mocks
import {Mock_EverclearPayment} from
    "test/modules/paymentProcessor/bridging/abstracts/mocks/Mock_EverclearPayment.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import "forge-std/console2.sol";

contract PP_Connext_Crosschain_v1_Test is ModuleTest {
    PP_Connext_Crosschain_v1_Exposed public paymentProcessor;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20PaymentClientBaseV1Mock paymentClient;
    IWETH public weth;

    uint public chainId;

    // Add these as contract state variables
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    uint maxFee = 0;
    uint ttl = 1;
    bytes executionData;
    bytes invalidExecutionData;

    uint constant MINTED_SUPPLY = 1000 ether;

    function setUp() public {
        // Set chain ID for test environment
        chainId = block.chainid;

        // Prepare execution data for bridge operations
        executionData = abi.encode(maxFee, ttl);
        invalidExecutionData = abi.encode(address(0));

        // Deploy mock contracts and set addresses
        everclearPaymentMock = new Mock_EverclearPayment();
        mockEverClearSpoke = address(everclearPaymentMock);
        mockWeth = address(weth);

        // Deploy payment processor via clone
        address impl = address(new PP_Connext_Crosschain_v1_Exposed());
        paymentProcessor = PP_Connext_Crosschain_v1_Exposed(Clones.clone(impl));

        _setUpOrchestrator(paymentProcessor);
        _authorizer.setIsAuthorized(address(this), true);

        // Initialize payment processor with config
        bytes memory configData = abi.encode(mockEverClearSpoke, mockWeth);
        paymentProcessor.init(_orchestrator, _METADATA, configData);

        // Deploy and add payment client through timelock process
        impl = address(new ERC20PaymentClientBaseV1Mock());
        paymentClient = ERC20PaymentClientBaseV1Mock(Clones.clone(impl));
        _orchestrator.initiateAddModuleWithTimelock(address(paymentClient));
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
        _orchestrator.executeAddModule(address(paymentClient));

        // Configure payment client
        paymentClient.init(_orchestrator, _METADATA, bytes(""));
        paymentClient.setIsAuthorized(address(paymentProcessor), true);
        paymentClient.setToken(_token);

        _setupInitialBalances();
    }

    /* Test initialization
        └── When the contract is initialized
            ├── Then it should set the orchestrator correctly
            └── Then it should set up Connext configuration properly
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    /* Test interface support
        ├── When checking IModule_v1 interface
        │   └── Then it should return true
        ├── When checking ICrossChainBase_v1 interface
        │   └── Then it should return true
        └── When checking random interface
            └── Then it should return false
    */
    function testSupportsInterface() public {
        // Test for IModule_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(type(IModule_v1).interfaceId)
        );

        // Test for ICrossChainBase_v1 interface
        assertTrue(
            paymentProcessor.supportsInterface(
                type(ICrossChainBase_v1).interfaceId
            )
        );

        // Test for a non-supported interface (using a random interface ID)
        assertFalse(paymentProcessor.supportsInterface(0xffffffff));
    }

    /* Test reinitialization protection
        └── When trying to reinitialize an already initialized contract
            └── Then it should revert with InvalidInitialization
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    /* Test single payment processing
    └── Given a valid payment order
    └── When processing through Connext bridge
        └── Then should emit PaymentProcessed event
            ├── And should create Connext intent
    └── When checking bridge data
            └── Then a valid intent ID should be stored
    */
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
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            testRecipient,
            address(_token),
            testAmount,
            block.timestamp,
            0,
            block.timestamp + 1 days
        );

        // Process payments
        paymentProcessor.processPayments(client, executionData);
        bytes32 intentId =
            paymentProcessor.intentId(address(paymentClient), testRecipient);
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
        );
    }

    /* Test multiple payment processing
    └── Given multiple valid payment orders
    └── When processing cross-chain payments
        └── Then it should emit PaymentProcessed events for each payment
            ├── And it should batch transfer tokens correctly
            └── And it should create multiple cross-chain intents

    .
    └── When checking bridge data
    └── Then it should contain valid intent IDs
    */
    function testProcessMultiplePayments_worksGivenMultipleValidPaymentOrders(
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
            emit IPaymentProcessor_v1.PaymentOrderProcessed(
                address(paymentClient),
                setupRecipients[i],
                address(_token),
                setupAmounts[i],
                block.timestamp,
                0,
                block.timestamp + 1 days
            );
        }

        // Process payments
        paymentProcessor.processPayments(client, executionData);
        //should be checking in the mock for valid bridge data
        for (uint i = 0; i < numRecipients; i++) {
            bytes32 intentId = paymentProcessor.intentId(
                address(paymentClient), setupRecipients[i]
            );
            assertEq(
                uint(everclearPaymentMock.status(intentId)),
                uint(Mock_EverclearPayment.IntentStatus.ADDED)
            );
        }
    }

    /* Test empty payment processing
        └── When processing with no payment orders
            ├── Then it should complete successfully
            └── And the bridge data should remain empty
    */
    function test_ProcessPayments_noPayments() public {
        // Process payments and verify _bridgeData mapping is not updated
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    /* Test invalid execution data
        └── When processing with invalid Connext parameters
            └── Then it should revert
    */
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
        paymentProcessor.processPayments(client, invalidExecutionData);
    }

    /* Test empty execution data
        ├── Given empty execution data bytes
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidExecutionData
    */
    function testProcessPayments_revertsGivenEmptyExecutionData(
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
        paymentProcessor.processPayments(client, bytes(""));
    }

    /* Test invalid recipient
        ├── Given a payment order with address(0) recipient
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidRecipient
    */
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
        paymentProcessor.processPayments(client, executionData);
    }

    /* Test invalid amount
        ├── Given a payment order with zero amount
        │   └── When attempting to process payment
        │       └── Then it should revert with InvalidAmount
    */
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
        paymentProcessor.processPayments(client, executionData);
    }

    /* Test bridge data storage
        ├── Given a valid payment order
        │   └── When processing payment
        │       └── Then bridge data should not be empty
        │           └── And intent ID should be stored correctly
                    └── And intent status should be ADDED in Everclear spoke
    */
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
        paymentProcessor.processPayments(client, executionData);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) != keccak256(bytes("")),
            "Bridge data should not be empty"
        );

        bytes32 intentId = bytes32(paymentProcessor.getBridgeData(0));
        assertEq(
            uint(everclearPaymentMock.status(intentId)),
            uint(Mock_EverclearPayment.IntentStatus.ADDED)
        );
    }

    /* Test empty bridge data
        └── When checking bridge data with no processed payments
            └── Then it should return empty bytes
    */
    function test_returnsEmptyBridgeData() public {
        IERC20PaymentClientBase_v1 client =
            IERC20PaymentClientBase_v1(address(paymentClient));
        // Process payments and verify _bridgeData mapping is updated
        paymentProcessor.processPayments(client, executionData);
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
    }

    /* Test insufficient balance
       Given payment amount exceeds available balance
        When attempting to process payment
      Then it should revert with ERC20InsufficientBalance
    */
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
                _token.balanceOf(address(paymentProcessor)),
                testAmount
            )
        );
        paymentProcessor.processPayments(client, executionData);
    }

    /* Test edge case amounts
        └── Given payment processor has exactly required amount
            └── When processing payment
                └── Then it should process successfully
                    └── And should emit PaymentProcessed event
                    └── And should handle exact balance correctly
    */
    function testFuzz_ProcessPayments_EdgeCaseAmounts(
        address testRecipient,
        uint96 testAmount
    ) public {
        vm.assume(testAmount > 0 && testAmount <= MINTED_SUPPLY);
        // Assumption
        vm.assume(testRecipient != address(0));

        // Setup - Clear existing balance
        uint currentBalance = _token.balanceOf(address(paymentProcessor));
        if (currentBalance > 0) {
            vm.prank(address(paymentProcessor));
            _token.transfer(address(1), currentBalance);
        }

        // Setup - Mint exact amount needed
        _token.mint(address(paymentProcessor), testAmount);

        _setupSinglePayment(testRecipient, testAmount);

        // Expectations
        vm.expectEmit(true, true, true, true);
        emit IPaymentProcessor_v1.PaymentOrderProcessed(
            address(paymentClient),
            testRecipient,
            address(_token),
            testAmount,
            block.timestamp,
            0,
            block.timestamp + 1 days
        );

        // Action
        paymentProcessor.processPayments(
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
                paymentToken: address(_token),
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
        _token.mint(address(this), MINTED_SUPPLY);
        _token.approve(address(paymentProcessor), type(uint).max);

        _token.mint(address(paymentProcessor), MINTED_SUPPLY); // Mint _tokens to processor
        vm.prank(address(paymentProcessor));
        _token.approve(address(paymentProcessor), type(uint).max); // Processor approves bridge logic
    }
}
