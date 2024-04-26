// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {IBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IBondingCurveBase_v1.sol";
import {IRedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/interfaces/IRedeemingBondingCurveBase_v1.sol";
import {IFM_BC_Bancor_Redeeming_VirtualSupply_v1} from
    "@fm/bondingCurve/interfaces/IFM_BC_Bancor_Redeeming_VirtualSupply_v1.sol";
import {IVirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualIssuanceSupplyBase_v1.sol";
import {IVirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/interfaces/IVirtualCollateralSupplyBase_v1.sol";
import {IOrchestrator_v1} from
    "src/orchestrator/interfaces/IOrchestrator_v1.sol";
import {IFundingManager_v1} from "@fm/IFundingManager_v1.sol";

// Internal Dependencies
import {Module_v1} from "src/modules/base/Module_v1.sol";
import {RedeemingBondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/RedeemingBondingCurveBase_v1.sol";
import {BondingCurveBase_v1} from
    "@fm/bondingCurve/abstracts/BondingCurveBase_v1.sol";
import {VirtualCollateralSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualCollateralSupplyBase_v1.sol";
import {VirtualIssuanceSupplyBase_v1} from
    "@fm/bondingCurve/abstracts/VirtualIssuanceSupplyBase_v1.sol";
import {IBancorFormula} from "@fm/bondingCurve/interfaces/IBancorFormula.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/**
 * @title   Bancor Virtual Supply Bonding Curve Funding Manager
 *
 * @notice  This contract enables the issuance and redeeming of tokens on a bonding curve, using
 *          a virtual supply for both the issuance and the collateral as input. It integrates
 *          Aragon's Bancor Formula to manage the calculations for token issuance and redemption
 *          rates based on specified reserve ratios.
 *
 * @dev     Inherits {BondingCurveBase_v1}, {RedeemingBondingCurveBase_v1}, {VirtualIssuanceSupplyBase_v1},
 *          and {VirtualCollateralSupplyBase_v1}. Implements formulaWrapper functions for bonding curve
 *          calculations using the Bancor formula. {Orchestrator_v1} Owner or Manager manages
 *          configuration such as virtual supplies and reserve ratios. Ensure interaction adheres to
 *          defined transactional limits and decimal precision requirements to prevent computational
 *          overflows or underflows.
 *
 * @author  Inverter Network
 */
contract FM_BC_Bancor_Redeeming_VirtualSupply_v1 is
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1,
    VirtualIssuanceSupplyBase_v1,
    VirtualCollateralSupplyBase_v1,
    RedeemingBondingCurveBase_v1
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(
            VirtualIssuanceSupplyBase_v1,
            VirtualCollateralSupplyBase_v1,
            RedeemingBondingCurveBase_v1
        )
        returns (bool)
    {
        return interfaceId
            == type(IFM_BC_Bancor_Redeeming_VirtualSupply_v1).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Bancor Formula used to calculate the issuance and redeeming amount.
    IBancorFormula public formula;
    /// @dev Value is used to convert deposit amount to 18 decimals,
    /// which is required by the Bancor formula
    uint8 private constant eighteenDecimals = 18;
    /// @dev The reserve ratio for buying determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForBuying;
    /// @dev The reserve ratio for selling determines the rate of price growth. It is a measure of the fraction
    /// of the Token's value that is held in reserve. The value is a number between 0 and 100%,
    /// expressed in PPM. A higher reserve ratio means slower price growth. See Bancor Formula contract
    /// for reference.
    uint32 internal reserveRatioForSelling;
    /// @dev Parts per million used for calculation the reserve ratio for the Bancor formula.
    uint32 internal constant PPM = 1_000_000;
    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 private _token;
    /// @dev Token decimals of the Orchestrator_v1 token, which is used as collateral and stores within
    /// implementation for gas saving.
    uint8 internal collateralTokenDecimals;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module_v1
    function init(
        IOrchestrator_v1 orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module_v1) initializer {
        __Module_init(orchestrator_, metadata);

        address _acceptedToken;
        IssuanceToken memory issuanceToken;
        BondingCurveProperties memory bondingCurveProperties;

        (issuanceToken, bondingCurveProperties, _acceptedToken) = abi.decode(
            configData, (IssuanceToken, BondingCurveProperties, address)
        );

        __ERC20_init(
            string(abi.encodePacked(issuanceToken.name)),
            string(abi.encodePacked(issuanceToken.symbol))
        );

        _token = IERC20(_acceptedToken);

        // Store token decimals for collateral
        collateralTokenDecimals = IERC20Metadata(address(_token)).decimals();

        // Set token decimals for issuance token
        _setTokenDecimals(issuanceToken.decimals);
        // Set formula contract
        formula = IBancorFormula(bondingCurveProperties.formula);
        // Set virtual issuance token supply
        _setVirtualIssuanceSupply(bondingCurveProperties.initialIssuanceSupply);
        // Set virtual collateral supply
        _setVirtualCollateralSupply(
            bondingCurveProperties.initialCollateralSupply
        );
        // Set reserve ratio for buying
        _setReserveRatioForBuying(bondingCurveProperties.reserveRatioForBuying);
        // Set reserve ratio for selling
        _setReserveRatioForSelling(
            bondingCurveProperties.reserveRatioForSelling
        );
        // Set buy fee percentage
        _setBuyFee(bondingCurveProperties.buyFee);
        // Set sell fee percentage
        _setSellFee(bondingCurveProperties.sellFee);
        // Set buying functionality to open if true. By default buying is false
        if (bondingCurveProperties.buyIsOpen == true) _openBuy();
        // Set selling functionality to open if true. By default selling is false
        if (bondingCurveProperties.sellIsOpen == true) _openSell();
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Buy tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BondingCurveBase_v1)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        _virtualBuyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Buy tokens for the sender's address. This function is subject
    /// to a transactional limit, determined by the deposit token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_buyOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^38). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^20).
    /// While this is substantially large, it is crucial to be aware of this constraint.
    /// Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(BondingCurveBase_v1)
        buyingIsEnabled
    {
        _virtualBuyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Redeem tokens on behalf of a specified receiver address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the receiver address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveBase_v1)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        _virtualSellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Sell collateral for the sender's address. This function is subject
    /// to a transactional limit, determined by the issuing token's decimal precision and the underlying
    /// bonding curve algorithm.
    /// @dev Redirects to the internal function `_sellOrder` by passing the sender's address and deposit amount.
    /// Important: The Bancor Formula has an upper computational limit of (10^26). For tokens with
    /// 18 decimal places, this effectively leaves a maximum allowable deposit amount of (10^8), or
    /// 100,000,000. Transactions exceeding this limit will be reverted.
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveBase_v1)
        sellingIsEnabled
    {
        _virtualSellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function getReserveRatioForBuying() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function getReserveRatioForSelling() external view returns (uint32) {
        return reserveRatioForBuying;
    }

    /// @notice Calculates and returns the static price for buying the issuance token.
    /// The return value is formatted in PPM.
    /// @return uint The static price for buying the issuance token
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveBase_v1)
        returns (uint)
    {
        return _staticPricePPM(
            virtualIssuanceSupply,
            virtualCollateralSupply,
            reserveRatioForBuying
        );
    }

    /// @notice Calculates and returns the static price for selling the issuance token.
    /// The return value is formatted in PPM.
    /// @return uint The static price for selling the issuance token
    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint)
    {
        return _staticPricePPM(
            virtualIssuanceSupply,
            virtualCollateralSupply,
            reserveRatioForSelling
        );
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function calculatePurchaseReturn(uint _depositAmount)
        external
        view
        returns (uint mintAmount)
    {
        if (_depositAmount == 0) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidDepositAmount();
        }
        if (buyFee > 0) {
            (_depositAmount, /* feeAmount */ ) =
                _calculateNetAmountAndFee(_depositAmount, buyFee);
        }
        return _issueTokensFormulaWrapper(_depositAmount);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function calculateSaleReturn(uint _depositAmount)
        external
        view
        returns (uint redeemAmount)
    {
        if (_depositAmount == 0) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidDepositAmount();
        }
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);
        if (sellFee > 0) {
            (redeemAmount, /* feeAmount */ ) =
                _calculateNetAmountAndFee(redeemAmount, sellFee);
        }
        return redeemAmount;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager_v1
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function mintIssuanceTokenTo(address _receiver, uint _amount)
        external
        onlyOrchestratorOwner
        validReceiver(_receiver)
    {
        _mint(_receiver, _amount);
    }

    /// @inheritdoc IVirtualIssuanceSupplyBase_v1
    function setVirtualIssuanceSupply(uint _virtualSupply)
        external
        override(VirtualIssuanceSupplyBase_v1)
        onlyOrchestratorOwner
    {
        _setVirtualIssuanceSupply(_virtualSupply);
    }

    /// @inheritdoc IVirtualCollateralSupplyBase_v1
    function setVirtualCollateralSupply(uint _virtualSupply)
        external
        override(VirtualCollateralSupplyBase_v1)
        onlyOrchestratorOwner
    {
        _setVirtualCollateralSupply(_virtualSupply);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function setReserveRatioForBuying(uint32 _reserveRatio)
        external
        onlyOrchestratorOwner
    {
        _setReserveRatioForBuying(_reserveRatio);
    }

    /// @inheritdoc IFM_BC_Bancor_Redeeming_VirtualSupply_v1
    function setReserveRatioForSelling(uint32 _reserveRatio)
        external
        onlyOrchestratorOwner
    {
        _setReserveRatioForSelling(_reserveRatio);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Calculates the amount of tokens to mint for a given deposit amount using the Bancor formula.
    /// This internal function is an override of BondingCurveBase_v1's abstract function.
    /// It handles decimal conversions and calculations through the bonding curve.
    /// @param _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveBase_v1)
        returns (uint mintAmount)
    {
        // Convert virtual supply and balance to 18 decimals
        uint decimalConvertedVirtualIssuanceSupply =
        _convertAmountToRequiredDecimal(
            virtualIssuanceSupply, decimals(), eighteenDecimals
        );

        uint decimalConvertedVirtualCollateralSupply =
        _convertAmountToRequiredDecimal(
            virtualCollateralSupply, collateralTokenDecimals, eighteenDecimals
        );

        // Convert depositAmount to 18 decimals, which is required by Bancor formula
        uint decimalConvertedDepositAmount = _convertAmountToRequiredDecimal(
            _depositAmount, collateralTokenDecimals, eighteenDecimals
        );

        // Calculate mint amount through bonding curve
        uint decimalConvertedMintAmount = formula.calculatePurchaseReturn(
            decimalConvertedVirtualIssuanceSupply,
            decimalConvertedVirtualCollateralSupply,
            reserveRatioForBuying,
            decimalConvertedDepositAmount
        );
        // Convert mint amount to issuing token decimals
        mintAmount = _convertAmountToRequiredDecimal(
            decimalConvertedMintAmount, eighteenDecimals, decimals()
        );
    }

    /// @dev Calculates the static price for either selling or buying the issuance token,
    /// based on the provided issuance token supply, collateral supply, and buy or sell reserve ratio.
    /// Note: The reserve ratio specifies whether the sell or buy price is returned.
    /// The formula used is: PPM * PPM * collateralSupply / (issuanceTokenSupply * reserveRatio).
    /// The formula is based on Aragon's BatchedBancorMarketMaker, which can be found here:
    /// https://github.com/AragonBlack/fundraising/blob/5ad1332955bab9d36cfad345ae92b7ad7dc0bdbe/apps/batched-bancor-market-maker/contracts/BatchedBancorMarketMaker.sol#L415
    /// @param _issuanceTokenSupply The total supply of the issuance tokens.
    /// @param _collateralSupply The total supply of the collateral held by the FundingManager.
    /// @param _reserveRatio The reserve ratio, specified as either sell or buy reserve ratio.
    /// @return uint The calculated static price for the specified operation, formatted in PPM
    function _staticPricePPM(
        uint _issuanceTokenSupply,
        uint _collateralSupply,
        uint32 _reserveRatio
    ) internal pure returns (uint) {
        return uint(PPM) * uint(PPM) * _collateralSupply
            / (_issuanceTokenSupply * uint(_reserveRatio));
    }

    /// @dev Calculates the amount of collateral to be received when redeeming a given amount of issuance tokens.
    /// This internal function is an override of RedeemingBondingCurveBase_v1's abstract function.
    /// It handles decimal conversions and calculations through the bonding curve. Note the Bancor formula assumes 18 decimals for all tokens
    /// @param _depositAmount The amount of issuance tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveBase_v1)
        returns (uint redeemAmount)
    {
        // Convert virtual supply and balance to 18 decimals
        uint decimalConvertedVirtualIssuanceSupply =
        _convertAmountToRequiredDecimal(
            virtualIssuanceSupply, decimals(), eighteenDecimals
        );

        uint decimalConvertedVirtualCollateralSupply =
        _convertAmountToRequiredDecimal(
            virtualCollateralSupply, collateralTokenDecimals, eighteenDecimals
        );

        // Convert depositAmount to 18 decimals, which is required by Bancor formula
        uint decimalConvertedDepositAmount = _convertAmountToRequiredDecimal(
            _depositAmount, decimals(), eighteenDecimals
        );

        // Calculate redeem amount through bonding curve
        uint decimalConvertedRedeemAmount = formula.calculateSaleReturn(
            decimalConvertedVirtualIssuanceSupply,
            decimalConvertedVirtualCollateralSupply,
            reserveRatioForSelling,
            decimalConvertedDepositAmount
        );

        // Convert redeem amount to collateral decimals
        redeemAmount = _convertAmountToRequiredDecimal(
            decimalConvertedRedeemAmount,
            eighteenDecimals,
            collateralTokenDecimals
        );
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Sets the number of decimals for the token.
    /// This function overrides the internal function set in BondingCurveBase_v1, adding
    /// an input validation specific for the Bancor Formula utilizing implementation, after which
    /// it updates the `tokenDecimals` state variable.
    /// @param _decimals The number of decimals to set for the token.
    function _setTokenDecimals(uint8 _decimals)
        internal
        override(BondingCurveBase_v1)
    {
        // An input verification is needed here since the Bancor formula, which determines the
        // issucance price, utilizes PPM for its computations. This leads to a precision loss
        // that's too significant to be acceptable for tokens with fewer than 7 decimals.
        if (_decimals < 7 || _decimals < collateralTokenDecimals) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidTokenDecimal();
        }
        tokenDecimals = _decimals;
    }

    /// @dev Executes a buy order and updates the virtual supply of tokens and collateral.
    /// This function internally calls `_buyOrder` to get the issuing amount and updates the
    /// virtual balances accordingly.
    /// @param _receiver The address of the recipient of the issued tokens.
    /// @param _depositAmount The amount of collateral deposited for the buy order.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function _virtualBuyOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    ) internal {
        (uint amountIssued, uint feeAmount) =
            _buyOrder(_receiver, _depositAmount, _minAmountOut);
        _addVirtualIssuanceAmount(amountIssued);
        _addVirtualCollateralAmount(_depositAmount - feeAmount);
    }

    /// @dev Executes a sell order and updates the virtual supply of issuance and collateral.
    /// This function internally calls `_sellOrder` to get the redeem amount and updates the
    /// virtual balances accordingly.
    /// @param _receiver The address that will receive the redeem amount.
    /// @param _depositAmount The amount of issuance tokens that are being sold.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function _virtualSellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    ) internal {
        (uint redeemAmount, uint feeAmount) =
            _sellOrder(_receiver, _depositAmount, _minAmountOut);
        _subVirtualIssuanceAmount(_depositAmount);
        _subVirtualCollateralAmount(redeemAmount + feeAmount);
    }

    /// @dev Sets the reserve ratio for buying tokens.
    /// The function will revert if the ratio is greater than the constant PPM.
    ///
    /// @param _reserveRatio The reserve ratio to be set for buying tokens. Must be <= PPM.
    function _setReserveRatioForBuying(uint32 _reserveRatio) internal {
        if (_reserveRatio == 0) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();
        }
        emit BuyReserveRatioSet(_reserveRatio, reserveRatioForBuying);
        reserveRatioForBuying = _reserveRatio;
    }

    /// @dev Sets the reserve ratio for selling tokens.
    /// Similar to its counterpart for buying, this function sets the reserve ratio for selling tokens.
    /// The function will revert if the ratio is greater than the constant PPM.
    ///
    /// @param _reserveRatio The reserve ratio to be set for selling tokens. Must be <= PPM.
    function _setReserveRatioForSelling(uint32 _reserveRatio) internal {
        if (_reserveRatio == 0) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();
        }
        if (_reserveRatio > PPM) {
            revert
                Module__FM_BC_Bancor_Redeeming_VirtualSupply__InvalidReserveRatio();
        }
        emit SellReserveRatioSet(_reserveRatio, reserveRatioForSelling);
        reserveRatioForSelling = _reserveRatio;
    }

    /// @dev Converts an amount to a required decimal representation.
    /// This function is useful for handling tokens with different decimal places.
    /// It takes care of both upscaling and downscaling the decimals based on the required decimals.
    ///
    /// @param _amount The amount to be converted.
    /// @param _tokenDecimals The current decimal places of the token.
    /// @param _requiredDecimals The required decimal places for the token.
    ///
    /// @return The converted amount with required decimal places.
    function _convertAmountToRequiredDecimal(
        uint _amount,
        uint8 _tokenDecimals,
        uint8 _requiredDecimals
    ) internal pure returns (uint) {
        // If the token decimal is the same as required decimal, return amount
        if (_tokenDecimals == _requiredDecimals) {
            return _amount;
        }
        // If the decimal of token is > required decimal, calculate conversion rate and
        // return amount converted to required decimal
        if (_tokenDecimals > _requiredDecimals) {
            uint conversionFactor = (10 ** (_tokenDecimals - _requiredDecimals));
            return (_amount / conversionFactor);
        } else {
            // If the decimal of token is < required decimal, calculate conversion rate and
            // return amount converted to required decimals
            uint conversionFactor = (10 ** (_requiredDecimals - _tokenDecimals));
            return (_amount * conversionFactor);
        }
    }
}