// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";

// Internal Interfaces
import {IProposal} from "src/interfaces/IProposal.sol";
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

contract Proposal is IProposal, ModuleManager, PausableUpgradeable {
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyAuthorized() {
        if (!authorizer.isAuthorized(msg.sender)) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The proposal's id.
    uint private _proposalId;

    /// @dev The list of funders.
    address[] private _funders;

    /// @inheritdoc IProposal
    IAuthorizer public override (IProposal) authorizer;

    //--------------------------------------------------------------------------
    // Initializer

    function init(
        uint proposalId,
        address[] calldata funders,
        address[] calldata modules,
        IAuthorizer authorizer_
    ) external initializer {
        _proposalId = proposalId;
        _funders = funders;

        __Pausable_init();
        __ModuleManager_init(modules);

        if (!isEnabledModule(address(authorizer_))) {
            revert Proposal__InvalidAuthorizer();
        }

        authorizer = authorizer_;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IProposal
    function executeTx(address target, bytes memory data)
        external
        onlyAuthorized
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (ok) {
            return returnData;
        } else {
            revert Proposal__ExecuteTxFailed();
        }
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }
}
