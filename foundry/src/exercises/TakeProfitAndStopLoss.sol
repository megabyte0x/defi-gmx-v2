// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {Order} from "../types/Order.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract TakeProfitAndStopLoss {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant usdc = IERC20(USDC);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    Oracle immutable oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    // Task 1 - Receive execution fee refund from GMX
    receive() external payable {}

    function _calculateLongOrderAcceptablePrice(
        uint256 ethPrice,
        bool isOpeningLong
    ) internal pure returns (uint256) {
        if (isOpeningLong) {
            return (ethPrice * 101 * 1e4) / 100;
        } else {
            return (ethPrice * 99 * 1e4) / 100;
        }
    }

    function _calculateStopLossTriggerPrice(uint256 ethPrice)
        internal
        pure
        returns (uint256)
    {
        return (ethPrice * 1e4 * 90) / 100;
    }

    function _calculateCloseLongTriggerPrice(uint256 ethPrice)
        internal
        pure
        returns (uint256)
    {
        return (ethPrice * 1e4 * 110) / 100;
    }
    // Task 2 - Create orders to
    // 1. Long ETH with USDC collateral
    // 2. Stop loss for ETH price below 90% of current price
    // 3. Take profit for ETH price above 110% of current price

    function createTakeProfitAndStopLossOrders(
        uint256 leverage,
        uint256 usdcAmount
    ) external payable returns (bytes32[] memory keys) {
        uint256 executionFee = 0.1 * 1e18;
        usdc.transferFrom(msg.sender, address(this), usdcAmount);
        keys = new bytes32[](3);

        // Task 2.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 2.2 - Send USDC to the order vault
        usdc.approve(ROUTER, usdcAmount);
        exchangeRouter.sendTokens(USDC, ORDER_VAULT, usdcAmount);

        // Task 2.3 - Create a long order to long ETH with USDC collateral
        uint256 usdcPrice = oracle.getPrice(CHAINLINK_USDC_USD);
        uint256 ethPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        uint256 sizeDeltaUsd = usdcPrice * usdcAmount * leverage * 1e16;

        IBaseOrderUtils.CreateOrderParams memory longOrder;
        IBaseOrderUtils.CreateOrderParamsAddresses memory longOrderAddresses =
        IBaseOrderUtils.CreateOrderParamsAddresses({
            receiver: address(this),
            cancellationReceiver: address(0),
            callbackContract: address(0),
            uiFeeReceiver: address(0),
            market: GM_TOKEN_ETH_WETH_USDC,
            initialCollateralToken: USDC,
            swapPath: new address[](0)
        });
        IBaseOrderUtils.CreateOrderParamsNumbers memory longOrderNumbers =
        IBaseOrderUtils.CreateOrderParamsNumbers({
            sizeDeltaUsd: sizeDeltaUsd,
            initialCollateralDeltaAmount: usdcAmount,
            triggerPrice: 0,
            acceptablePrice: _calculateLongOrderAcceptablePrice(ethPrice, true),
            executionFee: executionFee,
            callbackGasLimit: 0,
            minOutputAmount: 0,
            validFromTime: 0
        });

        longOrder = IBaseOrderUtils.CreateOrderParams({
            addresses: longOrderAddresses,
            numbers: longOrderNumbers,
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        bytes32 longOrderKey = exchangeRouter.createOrder(longOrder);

        // Task 2.4 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 2.5 - Create a stop loss for 90% of current ETH price

        IBaseOrderUtils.CreateOrderParams memory stopLossOrder;
        IBaseOrderUtils.CreateOrderParamsAddresses memory stopLossOrderAddresses =
        IBaseOrderUtils.CreateOrderParamsAddresses({
            receiver: address(this),
            cancellationReceiver: address(0),
            callbackContract: address(0),
            uiFeeReceiver: address(0),
            market: GM_TOKEN_ETH_WETH_USDC,
            initialCollateralToken: USDC,
            swapPath: new address[](0)
        });
        IBaseOrderUtils.CreateOrderParamsNumbers memory stopLossOrderNumbers =
        IBaseOrderUtils.CreateOrderParamsNumbers({
            sizeDeltaUsd: sizeDeltaUsd,
            initialCollateralDeltaAmount: usdcAmount,
            triggerPrice: _calculateStopLossTriggerPrice(ethPrice),
            acceptablePrice: 0,
            executionFee: executionFee,
            callbackGasLimit: 0,
            minOutputAmount: 0,
            validFromTime: block.timestamp
        });

        stopLossOrder = IBaseOrderUtils.CreateOrderParams({
            addresses: stopLossOrderAddresses,
            numbers: stopLossOrderNumbers,
            orderType: Order.OrderType.StopLossDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: true,
            referralCode: bytes32(uint256(0))
        });

        bytes32 stopLossOrderKey = exchangeRouter.createOrder(stopLossOrder);

        // Task 2.6 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 2.7 - Create an order to take profit above 110% of current price

        IBaseOrderUtils.CreateOrderParams memory closeLossOrder;
        IBaseOrderUtils.CreateOrderParamsAddresses memory
            closeLossOrderAddresses = IBaseOrderUtils
                .CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: USDC,
                swapPath: new address[](0)
            });
        IBaseOrderUtils.CreateOrderParamsNumbers memory closeLossOrderNumbers =
        IBaseOrderUtils.CreateOrderParamsNumbers({
            sizeDeltaUsd: sizeDeltaUsd,
            initialCollateralDeltaAmount: usdcAmount,
            triggerPrice: _calculateCloseLongTriggerPrice(ethPrice),
            acceptablePrice: _calculateLongOrderAcceptablePrice(ethPrice, false),
            executionFee: executionFee,
            callbackGasLimit: 0,
            minOutputAmount: 0,
            validFromTime: block.timestamp
        });

        closeLossOrder = IBaseOrderUtils.CreateOrderParams({
            addresses: closeLossOrderAddresses,
            numbers: closeLossOrderNumbers,
            orderType: Order.OrderType.LimitDecrease,
            decreasePositionSwapType: Order
                .DecreasePositionSwapType
                .SwapPnlTokenToCollateralToken,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        bytes32 closeLossOrderKey = exchangeRouter.createOrder(closeLossOrder);

        keys[0] = longOrderKey;
        keys[1] = stopLossOrderKey;
        keys[2] = closeLossOrderKey;
    }
}
