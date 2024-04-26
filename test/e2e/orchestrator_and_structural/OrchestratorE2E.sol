// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

//Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1,
    ModuleFactory_v1
} from "test/e2e/E2ETest.sol";

//SuT
import {
    IOrchestrator_v1,
    Orchestrator_v1
} from "src/orchestrator/Orchestrator_v1.sol";

// Modules that are used in this E2E test
import {IPaymentProcessor_v1} from
    "src/modules/paymentProcessor/IPaymentProcessor_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
import {IAuthorizer_v1} from "@aut/IAuthorizer_v1.sol";
import {
    ILM_PC_Bounties_v1, LM_PC_Bounties_v1
} from "@lm/LM_PC_Bounties_v1.sol";
import {
    IMetadataManager_v1,
    MetadataManager_v1
} from "src/modules/utils/MetadataManager_v1.sol";

//Beacon
import {InverterBeacon_v1} from "src/proxies/InverterBeacon_v1.sol";

/**
 * e2e PoC test to show how to create a new orchestrator via the {OrchestratorFactory_v1}.
 */
contract OrchestratorE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    //Orchestrator_v1 Metadata
    IMetadataManager_v1.ManagerMetadata ownerMetadata;
    IMetadataManager_v1.OrchestratorMetadata orchestratorMetadata;
    IMetadataManager_v1.MemberMetadata[] teamMetadata;

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // We also set up the LM_PC_Bounties_v1, even though we'll add it later
        setUpBountyManager();

        //==========================================
        //Set up Orchestrator_v1 Metadata

        ownerMetadata = IMetadataManager_v1.ManagerMetadata(
            "Name", address(0xBEEF), "TwitterHandle"
        );

        orchestratorMetadata = IMetadataManager_v1.OrchestratorMetadata(
            "Title",
            "DescriptionShort",
            "DescriptionLong",
            new string[](0),
            new string[](0)
        );

        orchestratorMetadata.externalMedias.push("externalMedia1");
        orchestratorMetadata.externalMedias.push("externalMedia2");
        orchestratorMetadata.externalMedias.push("externalMedia3");

        orchestratorMetadata.categories.push("category1");
        orchestratorMetadata.categories.push("category2");
        orchestratorMetadata.categories.push("category3");

        teamMetadata.push(
            IMetadataManager_v1.MemberMetadata(
                "Name", address(0xBEEF), "Something"
            )
        );
    }

    //We're adding and removing a Module during the lifetime of the orchestrator
    function testManageModulesLiveOnPorposal() public {
        // address(this) creates a new orchestrator.
        IOrchestratorFactory_v1.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory_v1.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        //Create Orchestrator_v1
        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //------------------------------------------------------------------------------------------------
        // Adding Module

        uint modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        //Create the module via the moduleFactory
        address bountyManager = moduleFactory.createModule(
            bountyManagerMetadata, orchestrator, bytes("")
        );

        //Add Module to the orchestrator
        orchestrator.addModule(bountyManager);

        assertEq((modulesBefore + 1), orchestrator.modulesSize()); // The orchestrator now has one more module

        //------------------------------------------------------------------------------------------------
        // Removing Module
        orchestrator.removeModule(bountyManager);

        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        //------------------------------------------------------------------------------------------------
        //In case there is a need to replace the  paymentProcessor / fundingManager / authorizer

        //Create the new modules via the moduleFactory
        address newPaymentProcessor = moduleFactory.createModule(
            simplePaymentProcessorMetadata, orchestrator, bytes("")
        );

        address newFundingManager = moduleFactory.createModule(
            rebasingFundingManagerMetadata,
            orchestrator,
            abi.encode(address(orchestrator.fundingManager().token()))
        );

        address[] memory initialAuthorizedAddresses = new address[](1);
        initialAuthorizedAddresses[0] = address(this);

        address newAuthorizer = moduleFactory.createModule(
            roleAuthorizerMetadata,
            orchestrator,
            abi.encode(initialAuthorizedAddresses)
        );

        modulesBefore = orchestrator.modulesSize(); // We store the number of modules the orchestrator has

        //We store the original module addresses
        address originalPaymentProcessor =
            address(orchestrator.paymentProcessor());
        address originalFundingManager = address(orchestrator.fundingManager());
        address originalAuthorizer = address(orchestrator.authorizer());

        //Replace the old modules with the new ones
        orchestrator.setPaymentProcessor(
            IPaymentProcessor_v1(newPaymentProcessor)
        );
        orchestrator.setFundingManager(IFundingManager_v1(newFundingManager));
        orchestrator.setAuthorizer(IAuthorizer_v1(newAuthorizer));

        //Assert post-state
        assertEq(modulesBefore, orchestrator.modulesSize()); // The orchestrator is back to the original number of modules

        assertEq(newPaymentProcessor, address(orchestrator.paymentProcessor()));
        assertEq(newFundingManager, address(orchestrator.fundingManager()));
        assertEq(newAuthorizer, address(orchestrator.authorizer()));

        assertFalse(orchestrator.isModule(originalPaymentProcessor));
        assertFalse(orchestrator.isModule(originalFundingManager));
        assertFalse(orchestrator.isModule(originalAuthorizer));
    }
}