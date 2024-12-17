// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

//--------------------------------------------------------------------------
// Imports

// External Dependencies
import {Test} from "forge-std/Test.sol";
import {Clones} from "@oz/proxy/Clones.sol";
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";
import {IWETH} from "src/modules/paymentProcessor/interfaces/IWETH.sol";
import "forge-std/console2.sol";

// Internal Dependencies
import {PP_Connext_Crosschain_v1} from
    "src/modules/paymentProcessor/PP_Connext_Crosschain_v1.sol";
import {CrossChainBase_v1} from
    "src/modules/paymentProcessor/abstracts/CrossChainBase_v1.sol";
import {ICrossChainBase_v1} from
    "src/modules/paymentProcessor/interfaces/ICrosschainBase_v1.sol";
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IPP_Crosschain_v1} from
    "src/modules/paymentProcessor/interfaces/IPP_Crosschain_v1.sol";
import {IModule_v1, IOrchestrator_v1} from "src/modules/base/IModule_v1.sol";
import {IERC20PaymentClientBase_v1} from
    "@lm/interfaces/IERC20PaymentClientBase_v1.sol";

// Tests and Mocks
import {CrossChainBase_v1_Exposed} from
    "test/modules/paymentProcessor/abstracts/CrossChainBase_v1_Exposed.sol";
import {PP_Connext_Crosschain_v1_Exposed} from
    "test/modules/paymentProcessor/abstracts/PP_Connext_Crosschain_v1_Exposed.sol";
import {Mock_EverclearPayment} from
    "test/modules/paymentProcessor/abstracts/mocks/Mock_EverclearPayment.sol";
import {
    IERC20PaymentClientBase_v1,
    ERC20PaymentClientBaseV1Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV1Mock.sol";
import {ModuleTest} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract PP_Connext_Crosschain_v1_Test is ModuleTest {
    //--------------------------------------------------------------------------
    // Constants
    uint constant MINTED_SUPPLY = 1000 ether;

    //--------------------------------------------------------------------------
    // Test Storage
    PP_Connext_Crosschain_v1_Exposed public paymentProcessor;
    Mock_EverclearPayment public everclearPaymentMock;
    ERC20PaymentClientBaseV1Mock paymentClient;
    IPP_Crosschain_v1 public crossChainBase;
    IWETH public weth;
    uint public chainId;

    // Bridge-related storage
    address public mockConnextBridge;
    address public mockEverClearSpoke;
    address public mockWeth;

    // Execution data storage
    uint maxFee = 0;
    uint ttl = 1;
    bytes executionData;
    bytes invalidExecutionData;

    //--------------------------------------------------------------------------
    // Setup Function

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

    //--------------------------------------------------------------------------
    // Initialization Tests

    /* Test initialization
    */
    function testInit() public override(ModuleTest) {
        assertEq(
            address(paymentProcessor.orchestrator()), address(_orchestrator)
        );
    }

    /* Test interface support
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

    /* Test reinitialization
    */
    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        paymentProcessor.init(_orchestrator, _METADATA, abi.encode(1));
    }

    //--------------------------------------------------------------------------
    // Payment Processing Tests

    /* Test single payment processing
    └── Given single valid payment order
        └── When processing cross-chain payments
            └── Then it should emit PaymentProcessed events for payment
                └── And it should create cross-chain intent
    */
    function testPublicProcessPayments_succeedsGivenSingleValidPaymentOrder(
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
                ├── And it should create multiple cross-chain intents
                └── And it should contain valid intent IDs
    */
    function testPublicProcessPayments_succeedsGivenMultipleValidPaymentOrders(
        uint8 numRecipients,
        address testRecipient,
        uint96 baseAmount
    ) public {
        // Assumptions to keep the test manageable and within bounds
        vm.assume(numRecipients > 0 && numRecipients <= 10);
        vm.assume(testRecipient != address(0));

        // Just make sure baseAmount * numRecipients doesn't exceed MINTED_SUPPLY
        vm.assume(
            baseAmount > 0 && baseAmount <= MINTED_SUPPLY / (numRecipients * 2)
        );

        // Setup mock payment orders
        address[] memory setupRecipients = new address[](numRecipients);
        uint[] memory setupAmounts = new uint[](numRecipients);

        for (uint i = 0; i < numRecipients; i++) {
            setupRecipients[i] = testRecipient;
            // Simple amount calculation without any Math.min nonsense
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
    function testPublicProcessPayments_succeedsGivenNoPaymentOrders() public {
        // Process payments and verify _bridgeData mapping is not updated
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );
        assertTrue(
            keccak256(paymentProcessor.getBridgeData(0)) == keccak256(bytes("")),
            "Bridge data should be empty"
        );
        assertEq(
            paymentProcessor.intentId(address(paymentClient), address(0)),
            bytes32(0)
        );
    }

    //--------------------------------------------------------------------------
    // Error Case Tests

    /* Test invalid execution data
        └── When processing with invalid Connext parameters
            └── Then it should revert
    */
    function testPublicProcessPayments_revertsGivenInvalidExecutionData(
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
    function testPublicProcessPayments_revertsGivenEmptyExecutionData(
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
    function testPublicProcessPayments_revertsGivenInvalidRecipient(
        uint testAmount
    ) public {
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
    function testPublicProcessPayments_revertsGivenInvalidAmount(
        address testRecipient
    ) public {
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
    function testPublicProcessPayments_worksGivenCorrectBridgeData(
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
        ── When checking bridge data with no added payments
            └── Then it should return empty bytes
    */
    function testPublicProcessPayments_worksGivenEmptyBridgeData() public {
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
        └── Given payment amount exceeds available balance
            └── When attempting to process payment
                └── Then it should revert with ERC20InsufficientBalance
    */
    function testPublicProcessPayments_revertsGivenInsufficientBalance(
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
    function testPublicProcessPayments_worksGivenEdgeCaseAmounts(
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

    /* Test retry failed transfer
    └── Given a failed transfer
        └── When retrying with valid execution data
            └── Then it should create a new intent
                └── And clear the failed transfer record
                └── And emit FailedTransferRetried event
    */
    function testRetryFailedTransfer_succeeds() public {
        // Setup
        address recipient = address(0xBEEF);
        uint amount = 1 ether;

        // Setup initial payment
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _setupSinglePayment(recipient, amount);

        // First attempt with high maxFee to force failure
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)),
            abi.encode(333, 1) // maxFee of 333 will cause failure
        );

        // Verify failed transfer was recorded
        assertEq(
            paymentProcessor.failedTransfers(
                address(paymentClient), recipient, bytes32(0)
            ),
            orders[0].amount
        );

        // Now retry with proper execution data
        vm.prank(address(paymentClient));
        paymentProcessor.retryFailedTransfer(
            address(paymentClient),
            recipient,
            bytes32(0),
            orders[0],
            abi.encode(0, 1) // proper maxFee and ttl
        );

        // Verify:
        // 1. Failed transfer record was cleared
        assertEq(
            paymentProcessor.failedTransfers(
                address(paymentClient), recipient, bytes32(0)
            ),
            0
        );

        // 2. New intent was created (should be non-zero)
        bytes32 newIntentId =
            paymentProcessor.intentId(address(paymentClient), recipient);
        assertTrue(newIntentId != bytes32(0));
    }

    /* Test cancel transfer
    └── Given a pending transfer
        └── When cancelled by the recipient
            └── Then it should clear the intent
                └── And return funds to recipient
                └── And emit TransferCancelled event
    */
    function testCancelTransfer_succeeds() public {
        // Setup
        address recipient = address(0xBEEF);

        uint amount = 1 ether;

        // Setup the payment and process it
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _setupSinglePayment(recipient, amount);
        paymentClient.addPaymentOrder(orders[0]);
        //call processPayments with maxFee = 333
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)),
            abi.encode(333, 1)
        );
        console2.log("Fucker who seneeed", address(this));
        // see if failed failedTransfers updates
        assertEq(
            paymentProcessor.failedTransfers(
                address(paymentClient), recipient, bytes32(0)
            ),
            orders[0].amount
        );

        uint failedIntentId = paymentProcessor.failedTransfers(
            address(paymentClient), recipient, bytes32(0)
        );
        console2.log("AMOUNT", failedIntentId);
        assertEq(failedIntentId, orders[0].amount);

        // Cancel as recipient
        vm.prank(address(paymentClient));
        paymentProcessor.cancelTransfer(
            address(paymentClient), recipient, bytes32(0), orders[0]
        );

        // Verify intentId was cleared
        assertEq(
            paymentProcessor.intentId(address(paymentClient), recipient),
            bytes32(0)
        );
    }

    /* Test cancel transfer by non-recipient
    └── Given a pending transfer
        └── When cancelled by someone other than recipient
            └── Then it should revert with InvalidAddress
    */
    function testCancelTransfer_revertsForNonRecipient(
        address testRecipient,
        address nonRecipient,
        uint testAmount
    ) public {
        vm.assume(testRecipient != address(0));
        vm.assume(nonRecipient != testRecipient);
        vm.assume(testAmount > 0 && testAmount < MINTED_SUPPLY);

        _setupSinglePayment(testRecipient, testAmount);

        // Process payment to create intent
        paymentProcessor.processPayments(
            IERC20PaymentClientBase_v1(address(paymentClient)), executionData
        );

        bytes32 pendingIntentId =
            paymentProcessor.intentId(address(paymentClient), testRecipient);

        // Create payment order for cancellation
        IERC20PaymentClientBase_v1.PaymentOrder memory order =
        IERC20PaymentClientBase_v1.PaymentOrder({
            recipient: testRecipient,
            paymentToken: address(_token),
            amount: testAmount,
            start: block.timestamp,
            cliff: 0,
            end: block.timestamp + 1 days
        });

        // Prank as non-recipient
        vm.prank(nonRecipient);

        vm.expectRevert(IModule_v1.Module__InvalidAddress.selector);
        paymentProcessor.cancelTransfer(
            address(paymentClient), testRecipient, pendingIntentId, order
        );
    }

    //--------------------------------------------------------------------------
    // Helper Functions

    function _setupSinglePayment(address _recipient, uint _amount)
        internal
        returns (IERC20PaymentClientBase_v1.PaymentOrder[] memory)
    {
        address[] memory setupRecipients = new address[](1);
        setupRecipients[0] = _recipient;
        uint[] memory setupAmounts = new uint[](1);
        setupAmounts[0] = _amount;

        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            _createPaymentOrders(1, setupRecipients, setupAmounts);
        return orders;
    }

    function _createPaymentOrders(
        uint orderCount,
        address[] memory recipients,
        uint[] memory amounts
    ) internal returns (IERC20PaymentClientBase_v1.PaymentOrder[] memory) {
        // Sanity checks for array lengths
        require(
            recipients.length == orderCount && amounts.length == orderCount,
            "Array lengths must match orderCount"
        );
        IERC20PaymentClientBase_v1.PaymentOrder[] memory orders =
            new IERC20PaymentClientBase_v1.PaymentOrder[](orderCount);
        //add payment order to client

        for (uint i = 0; i < orderCount; i++) {
            orders[i] = IERC20PaymentClientBase_v1.PaymentOrder({
                recipient: recipients[i],
                paymentToken: address(_token),
                amount: amounts[i],
                start: block.timestamp,
                cliff: 0,
                end: block.timestamp + 1 days
            });
            paymentClient.addPaymentOrder(orders[i]);
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
