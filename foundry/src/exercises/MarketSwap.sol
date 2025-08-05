// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IReader} from "../interfaces/IReader.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {Order} from "../types/Order.sol";
import {IBaseOrderUtils} from "../types/IBaseOrderUtils.sol";
import "../Constants.sol";

contract MarketSwap {
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant dai = IERC20(DAI);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);
    IDataStore constant dataStore = IDataStore(DATA_STORE);
    IReader constant reader = IReader(READER);

    // Task 1 - Receive execution fee refund from GMX
    receive() external payable {}

    // Task 2 - Create an order to swap WETH to DAI
    function createOrder(uint256 wethAmount)
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

        // Task 2.3 - Create an order to swap WETH to DAI

        address[] memory swapPath = new address[](2);
        swapPath[0] = GM_TOKEN_ETH_WETH_USDC;
        swapPath[1] = GM_TOKEN_SWAP_ONLY_USDC_DAI;

        IBaseOrderUtils.CreateOrderParams memory params = IBaseOrderUtils
            .CreateOrderParams({
            addresses: IBaseOrderUtils.CreateOrderParamsAddresses({
                receiver: address(this),
                cancellationReceiver: address(0),
                callbackContract: address(0),
                uiFeeReceiver: address(0),
                market: address(0),
                initialCollateralToken: WETH,
                swapPath: swapPath
            }),
            numbers: IBaseOrderUtils.CreateOrderParamsNumbers({
                sizeDeltaUsd: 0,
                initialCollateralDeltaAmount: 0,
                triggerPrice: 0,
                acceptablePrice: 0,
                executionFee: executionFee,
                callbackGasLimit: 0,
                minOutputAmount: 1,
                validFromTime: 0
            }),
            orderType: Order.OrderType.MarketSwap,
            decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
            isLong: false,
            shouldUnwrapNativeToken: false,
            autoCancel: false,
            referralCode: bytes32(uint256(0))
        });

        return exchangeRouter.createOrder(params);
    }

    // Task 3 - Get order
    function getOrder(bytes32 key) external view returns (Order.Props memory) {
        return reader.getOrder(DATA_STORE, key);
    }
}
