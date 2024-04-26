// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// Internal Dependencies
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";

// SuT
import {
    RedeemingBondingCurveBase_v1,
    IRedeemingBondingCurveBase_v1
} from "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";

import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract RedeemingBondingCurveBaseV1Mock is RedeemingBondingCurveBase_v1 {
    IBancorFormula public formula;

    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        (
            bytes32 _name,
            bytes32 _symbol,
            uint8 _decimals,
            address _formula,
            uint _buyFee,
            bool _buyIsOpen,
            bool _sellIsOpen
        ) = abi.decode(
            configData, (bytes32, bytes32, uint8, address, uint, bool, bool)
        );

        __ERC20_init(
            string(abi.encodePacked(_name)), string(abi.encodePacked(_symbol))
        );

        formula = IBancorFormula(_formula);

        _setTokenDecimals(_decimals);

        _setBuyFee(_buyFee);

        if (_buyIsOpen == true) _openBuy();

        if (_sellIsOpen == true) _openSell();
    }

    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override
        returns (uint)
    {
        // Since this is a mock, we will always mint the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        pure
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {
        // Since this is a mock, we will always redeem the same amount of tokens as have been deposited
        // Integration tests using the actual Formula can be found in the BancorFormulaFundingManagerTest.t.sol
        return _depositAmount;
    }

    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {}

    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {}

    //--------------------------------------------------------------------------
    // Mock access for internal functions

    function call_BPS() external pure returns (uint) {
        return BPS;
    }

    //--------------------------------------------------------------------------
    // Will be removed once we update base fundingManager

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return __Module_orchestrator.fundingManager().token();
    }
}