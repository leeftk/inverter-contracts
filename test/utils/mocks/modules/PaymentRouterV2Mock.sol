// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {
    IOrchestrator_v1
} from "src/factories/interfaces/IModuleFactory_v1.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {ERC20PaymentClientBase_v2} from "@lm/abstracts/ERC20PaymentClientBase_v2.sol";
import {LM_PC_PaymentRouter_v2} from "@lm/LM_PC_PaymentRouter_v2.sol";

/**
 * @title   Payment Router Cross Chain Mock
 * @notice  Mock contract that extends PaymentRouter to support cross-chain payments
 * @dev     This mock allows setting custom flags and data for cross-chain payments
 */
contract PaymentRouterV2Mock is LM_PC_PaymentRouter_v2 {
    // Additional flags for cross-chain payments
    uint8 public constant FLAG_MAX_FEE = 4;
    uint8 public constant FLAG_TTL = 5;

    // Storage for cross-chain specific data
    uint256 public maxFee;
    uint256 public ttl;
    uint256 public originChainId;
    uint256 public targetChainId;

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || 
               interfaceId == type(ERC20PaymentClientBase_v2).interfaceId;
    }



    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @notice Sets the max fee for cross-chain payments
    function setMaxFee(uint256 _maxFee) external {
        maxFee = _maxFee;
    }

    /// @notice Sets the TTL for cross-chain payments
    function setTTL(uint256 _ttl) external {
        ttl = _ttl;
    }

    /// @notice Sets the origin and target chain IDs
    function setChainIds(uint256 _originChainId, uint256 _targetChainId) external {
        originChainId = _originChainId;
        targetChainId = _targetChainId;
    }

    // @note - This should override the parent function
    /// allowing us to set flags and data for maxFee and ttl
    /// as well as the origin and target chain IDs
    /// and execution data
    // However I may be confuse on what we're actually mocking here and maybe we should be
    /// mocking the ERC20PaymentClientBase_v2 instead?

    function _assemblePaymentConfig(bytes32[] memory flagValues_)
        internal
        view
        override
        returns (bytes32 flags_, bytes32[] memory data_)
    {
        // Create new array with space for maxFee and ttl
        bytes32[] memory newFlagValues = new bytes32[](6); // Fixed size of 6 for cross-chain payments
        
        // Copy original values
        for (uint i = 0; i < flagValues_.length; i++) {
            newFlagValues[i] = flagValues_[i];
        }
        
        // Add maxFee and ttl at their correct positions
        newFlagValues[FLAG_MAX_FEE] = bytes32(maxFee);
        newFlagValues[FLAG_TTL] = bytes32(ttl);
        
        // Set flags to include MAX_FEE and TTL (bits 4 and 5)
        flags_ = bytes32(uint(0x3F)); // Binary: ...0011 1111
        
        // Return the flags and data directly without calling parent
        return (flags_, newFlagValues);
    }

   
}