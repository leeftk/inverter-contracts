// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";
import {E2EModuleRegistry} from "test/e2e/E2EModuleRegistry.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {IERC20PaymentClientBase_v2} from
    "@lm/interfaces/IERC20PaymentClientBase_v2.sol";
import {
    PP_Everclear_CrossChain_v1,
    IPP_Everclear_CrossChain_v1
} from "@pp/PP_Everclear_CrossChain_v1.sol";
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {IModule_v1} from "src/modules/base/IModule_v1.sol";
import {PaymentRouterV2Mock} from "test/utils/mocks/modules/PaymentRouterV2Mock.sol";
import {LM_PC_PaymentRouter_v2} from "@lm/LM_PC_PaymentRouter_v2.sol";

contract CrosschainPaymentProcessorE2E is E2ETest {
    // Collateral token constants
    string internal constant COLLATERAL_NAME = "Mock USDC";
    string internal constant COLLATERAL_SYMBOL = "M-USDC";
    uint8 internal constant COLLATERAL_DECIMALS = 18;

    // Contracts
    ERC20Mock collateralToken;
    IOrchestrator_v1 orchestrator;
    PP_Everclear_CrossChain_v1 paymentProcessor;
    FM_DepositVault_v1 depositVault;
    PaymentRouterV2Mock paymentRouter;
    ERC20Issuance_v1 issuanceToken;

    // Module Configurations array
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Addresses
    address everClearSpoke;
    address weth;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        everClearSpoke = makeAddr("everClearSpoke");
        weth = makeAddr("weth");

        // Create collateral token
        collateralToken = new ERC20Mock(COLLATERAL_NAME, COLLATERAL_SYMBOL);

        // 1. Funding Manager (Deposit Vault)
        setUpDepositVaultFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                depositVaultMetadata,
                abi.encode(address(collateralToken))  // Deposit vault takes token address as config
            )
        );

        // 2. Role Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, 
                abi.encode(address(this))
            )
        );

        // 3. Payment Processor
        setUpEverclearPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                everclearPaymentProcessorMetadata,
                abi.encode(everClearSpoke, weth)
            )
        );
        
        // 4. Payment Router Mock
        setUpPaymentRouterMock();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                paymentRouterMockMetadata,
                bytes("")
            )
        );
    }

    function test_e2e_CrosschainPaymentProcessor() public {
        // Initialize orchestrator and modules
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator = _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get module instances
        depositVault = FM_DepositVault_v1(
            address(orchestrator.fundingManager())
        );
        paymentProcessor = PP_Everclear_CrossChain_v1(
            address(orchestrator.paymentProcessor())
        );
        address[] memory modules = orchestrator.listModules();
        paymentRouter = PaymentRouterV2Mock(modules[3]);  // Get the payment router module from the modules array

        // Grant payment pusher role to this test contract
        LM_PC_PaymentRouter_v2(address(paymentRouter)).grantModuleRole(
            bytes32("PAYMENT_PUSHER"),  // Use the role string directly since we know it
            address(this)
        );

        // Set different chain IDs for cross-chain payment
        
        // 1. Deposit tokens into the deposit vault
        uint depositAmount = 1000 ether;
        collateralToken.mint(address(this), depositAmount);
        collateralToken.approve(address(depositVault), depositAmount);
        depositVault.deposit(depositAmount);

        // 2. Create payment order through the router
        address recipient = makeAddr("recipient");
        uint paymentAmount = 1000 ether;

        uint start = block.timestamp;
        uint cliff = block.timestamp + 7 days;
        uint end = block.timestamp + 14 days;

        // Push the payment through the payment router
        // @note - Not sure if maybe like this is correct or even needed?
        /// But calling this without the LM_PC_PaymentRouter_v2 wrapper throws an error
        //
       paymentRouter.pushPayment(
            recipient,
            address(collateralToken),
            paymentAmount,
            start,
            cliff,
            end
        );
    }
}

 

