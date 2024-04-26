// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Internal Dependencies:
import {E2EModuleRegistry} from "test/e2e/E2EModuleRegistry.sol";

import {Governor_v1} from "src/external/governance/Governor_v1.sol";

import {TransactionForwarder_v1} from
    "src/external/forwarder/TransactionForwarder_v1.sol";

// Factories
import {
    ModuleFactory_v1,
    IModuleFactory_v1
} from "src/factories/ModuleFactory_v1.sol";
import {
    OrchestratorFactory_v1,
    IOrchestratorFactory_v1
} from "src/factories/OrchestratorFactory_v1.sol";

// Orchestrator_v1
import {
    Orchestrator_v1,
    IOrchestrator_v1
} from "src/orchestrator/Orchestrator_v1.sol";

import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {BancorFormula} from "@fm/bondingCurve/formulas/BancorFormula.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// External Dependencies
import {TransparentUpgradeableProxy} from
    "@oz/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @dev Base contract for e2e tests.
 */
contract E2ETest is E2EModuleRegistry {
    //Governance Gontract
    Governor_v1 gov;

    // Factory instances.
    OrchestratorFactory_v1 orchestratorFactory;

    // Orchestrator_v1 implementation.
    Orchestrator_v1 orchestratorImpl;

    // Mock token for funding.
    ERC20Mock token;

    // Forwarder
    TransactionForwarder_v1 forwarder;

    address communityMultisig = address(0x11111);
    address teamMultisig = address(0x22222);

    function setUp() public virtual {
        // Basic Setup function. This function es overriden and expanded by child E2E tests

        //Deploy Governance Contract
        gov = Governor_v1(
            address(
                new TransparentUpgradeableProxy( //based on openzeppelins TransparentUpgradeableProxy
                    address(new Governor_v1()), //Implementation Address
                    communityMultisig, //Admin
                    bytes("") //data field that could have been used for calls, but not necessary
                )
            )
        );

        gov.init(communityMultisig, teamMultisig, 1 weeks);
        // Deploy a Mock funding token for testing.

        //Set gov as the default beacon owner
        DEFAULT_BEACON_OWNER = address(gov);

        token = new ERC20Mock("Mock", "MOCK");

        //Deploy a forwarder used to enable metatransactions
        forwarder = new TransactionForwarder_v1("TransactionForwarder_v1");

        // Deploy Orchestrator_v1 implementation.
        orchestratorImpl = new Orchestrator_v1(address(forwarder));

        // Deploy Factories.
        moduleFactory = new ModuleFactory_v1(address(gov), address(forwarder));

        orchestratorFactory = new OrchestratorFactory_v1(
            address(orchestratorImpl),
            address(moduleFactory),
            address(forwarder)
        );
    }

    // Creates an orchestrator with the supplied config and the stored module config.
    // Can be overriden, shouldn't need to
    // NOTE: It's important to send the module configurations in order, since it will copy from the array.
    // The order should be:
    //      moduleConfigurations[0]  => FundingManager
    //      moduleConfigurations[1]  => Authorizer
    //      moduleConfigurations[2]  => PaymentProcessor
    //      moduleConfigurations[3:] => Additional Logic Modules
    function _create_E2E_Orchestrator(
        IOrchestratorFactory_v1.OrchestratorConfig memory _config,
        IOrchestratorFactory_v1.ModuleConfig[] memory _moduleConfigurations
    ) internal virtual returns (IOrchestrator_v1) {
        // Prepare array of optional modules (hopefully can be made more succinct in the future)
        uint amtOfOptionalModules = _moduleConfigurations.length - 3;

        IOrchestratorFactory_v1.ModuleConfig[] memory optionalModules =
            new IOrchestratorFactory_v1.ModuleConfig[](amtOfOptionalModules);

        for (uint i = 0; i < amtOfOptionalModules; i++) {
            optionalModules[i] = _moduleConfigurations[i + 3];
        }

        // Create orchestrator

        return orchestratorFactory.createOrchestrator(
            _config,
            _moduleConfigurations[0],
            _moduleConfigurations[1],
            _moduleConfigurations[2],
            optionalModules
        );
    }
}