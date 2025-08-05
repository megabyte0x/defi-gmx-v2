// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {IReader} from "../interfaces/IReader.sol";
import {Order} from "../types/Order.sol";
import {Position} from "../types/Position.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract Short {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant usdc = IERC20(USDC);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    IDataStore constant dataStore = IDataStore(DATA_STORE);
    IReader constant reader = IReader(READER);
    Oracle immutable oracle;

    constructor(address _oracle) {
        oracle = Oracle(_oracle);
    }

    // Task 1 - Receive execution fee refund from GMX
    receive() external payable {}

    // Task 2 - Create an order to short ETH with USDC collateral

    function createShortOrder(uint256 leverage, uint256 usdcAmount)
        external
        payable
        returns (bytes32 key)
    {
        uint256 executionFee = 0.1 * 1e18;
        usdc.transferFrom(msg.sender, address(this), usdcAmount);

        // Task 2.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 2.2 - Send USDC to the order vault
        usdc.approve(ROUTER, usdcAmount);
        exchangeRouter.sendTokens(USDC, ORDER_VAULT, usdcAmount);

        // Task 2.3 - Create an order to short ETH with USDC collateral

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: USDC,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: _sizeDeltaUSD(leverage, usdcAmount),
                initialCollateralDeltaAmount: 0,
                acceptablePrice: _calculateAcceptablePrice(true),
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0,
                triggerPrice: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: false,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });
        return exchangeRouter.createOrder(params);
    }

    function _sizeDeltaUSD(uint256 leverage, uint256 usdAmount)
        internal
        view
        returns (uint256)
    {
        uint256 currentPrice = oracle.getPrice(CHAINLINK_USDC_USD);
        // 1e8 * 1e6 * 1 * 1e16 = 1e30
        return currentPrice * usdAmount * leverage * 1e16;
    }

    function _calculateAcceptablePrice(bool openingShort)
        internal
        view
        returns (uint256)
    {
        uint256 currentPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        uint256 acceptablePrice;
        if (openingShort) {
            acceptablePrice = (currentPrice * 90 * 1e4) / 100;
        } else {
            acceptablePrice = (currentPrice * 110 * 1e4) / 100;
        }
        return acceptablePrice;
    }

    // Task 3 - Get position key
    function getPositionKey() public view returns (bytes32 key) {
        return Position.getPositionKey(
            address(this), GM_TOKEN_ETH_WETH_USDC, USDC, false
        );
    }

    // Task 4 - Get position
    function getPosition(bytes32 key)
        public
        view
        returns (Position.Props memory)
    {
        return reader.getPosition(DATA_STORE, key);
    }

    // Task 5 - Create an order to close the short position created by this contract
    function createCloseOrder() external payable returns (bytes32 key) {
        uint256 executionFee = 0.1 * 1e18;

        // Task 5.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 5.2 - Create an order to close the short position
        bytes32 position_key = getPositionKey();
        Position.Props memory positionDetails = getPosition(position_key);

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: USDC,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: positionDetails.numbers.sizeInUsd,
                initialCollateralDeltaAmount: positionDetails.numbers.collateralAmount,
                triggerPrice: 0,
                acceptablePrice: _calculateAcceptablePrice(false),
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 1,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: false,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }
}
