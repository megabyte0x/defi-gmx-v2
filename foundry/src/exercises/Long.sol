// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {IReader} from "../interfaces/IReader.sol";
import {Order} from "../types/Order.sol";
import {Position} from "../types/Position.sol";
import {Market} from "../types/Market.sol";
import {MarketUtils} from "../types/MarketUtils.sol";
import {Price} from "../types/Price.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import {Oracle} from "../lib/Oracle.sol";
import "../Constants.sol";

contract Long {
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

    // Task 2 - Create an order to long ETH with WETH collateral
    function createLongOrder(uint256 leverage, uint256 wethAmount)
        external
        payable
        returns (bytes32 key)
    {
        uint256 executionFee = 0.1 * 1e18;
        weth.transferFrom(msg.sender, address(this), wethAmount);

        // Task 2.1 - Send execution fee to the order vault
        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 2.2 - Send WETH to the order vault
        weth.approve(ROUTER, wethAmount);
        exchangeRouter.sendTokens(WETH, ORDER_VAULT, wethAmount);

        // Task 2.3 - Create an order

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: GM_TOKEN_ETH_WETH_USDC,
                initialCollateralToken: WETH,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: _calculateDelta(leverage, wethAmount),
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: _calculateAcceptablePrice(true),
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 0,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketIncrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }

    function _calculateDelta(uint256 leverage, uint256 wethAmount)
        internal
        view
        returns (uint256)
    {
        uint256 currentPrice = oracle.getPrice(CHAINLINK_ETH_USD);

        return wethAmount * currentPrice * leverage * 1e4;
    }

    function _calculateAcceptablePrice(bool openingLong)
        internal
        view
        returns (uint256)
    {
        uint256 currentPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        if (openingLong) {
            return (currentPrice * 101 * 1e4) / 100;
        } else {
            return (currentPrice * 99 * 1e4) / 100;
        }
    }
    // Task 3 - Get position key

    function getPositionKey() public view returns (bytes32 key) {
        return Position.getPositionKey(
            address(this), GM_TOKEN_ETH_WETH_USDC, WETH, true
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

    // Task 5 - Get position profit and loss
    function getPositionPnlUsd(bytes32 key, uint256 ethPrice)
        external
        view
        returns (int256)
    {
        Position.Props memory position_details = getPosition(key);

        (int256 positionPnL,,) = reader.getPositionPnlUsd({
            dataStore: DATA_STORE,
            market: Market.Props({
                marketToken: GM_TOKEN_ETH_WETH_USDC,
                indexToken: WETH,
                longToken: WETH,
                shortToken: USDC
            }),
            prices: MarketUtils.MarketPrices({
                indexTokenPrice: Price.Props({
                    min: ethPrice * 1e30 / (1e8 * 1e18) * 99 / 100,
                    max: ethPrice * 1e30 / (1e8 * 1e18) * 101 / 100
                }),
                longTokenPrice: Price.Props({
                    min: ethPrice * 1e30 / (1e8 * 1e18) * 99 / 100,
                    max: ethPrice * 1e30 / (1e8 * 1e18) * 101 / 100
                }),
                shortTokenPrice: Price.Props({
                    min: 1 * 1e30 / 1e6 * 99 / 100,
                    max: 1 * 1e30 / 1e6 * 101 / 100
                })
            }),
            positionKey: key,
            sizeDeltaUsd: position_details.numbers.sizeInUsd
        });
        return positionPnL;
    }

    function _getMarketPrice() internal view returns (Price.Props memory) {
        uint256 currentPrice = oracle.getPrice(CHAINLINK_ETH_USD);
        return Price.Props({
            min: (currentPrice * 99 * 1e4) / 100,
            max: (currentPrice * 101 * 1e4) / 100
        });
    }

    // Task 6 - Create an order to close the long position created by this contract
    function createCloseOrder() external payable returns (bytes32 key) {
        uint256 executionFee = 0.1 * 1e18;

        // Task 6.1 - Get position

        bytes32 position_key = getPositionKey();
        Position.Props memory position_details = getPosition(position_key);

        // Task 6.2 - Send execution fee to the order vault

        exchangeRouter.sendWnt{value: executionFee}(ORDER_VAULT, executionFee);

        // Task 6.3 - Create an order

        uint256 position_size = position_details.numbers.sizeInUsd;
        uint256 collateral_amount = position_details.numbers.collateralAmount;

        uint256 acceptable_price = _calculateAcceptablePrice(false);

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: position_details.addresses.market,
                initialCollateralToken: position_details.addresses.collateralToken,
                swapPath: new address[](0)
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: position_size,
                initialCollateralDeltaAmount: collateral_amount,
                triggerPrice: 0,
                acceptablePrice: acceptable_price,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 1,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketDecrease,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: true,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }
}
