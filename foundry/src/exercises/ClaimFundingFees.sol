// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IExchangeRouter} from "../interfaces/IExchangeRouter.sol";
import {IDataStore} from "../interfaces/IDataStore.sol";
import {Keys} from "../lib/Keys.sol";
import "../Constants.sol";

contract ClaimFundingFees {
    IDataStore constant dataStore = IDataStore(DATA_STORE);
    IExchangeRouter constant exchangeRouter = IExchangeRouter(EXCHANGE_ROUTER);

    // Task 1 - Get claimable funding fee
    function getClaimableAmount(address market, address token)
        external
        view
        returns (uint256)
    {
        return dataStore.getUint(Keys.claimableFundingAmountKey(market, token));
    }

    // Task 2 - Claim funding fees
    function claimFundingFees() external {
        address[] memory markets = new address[](2);
        markets[0] = GM_TOKEN_ETH_WETH_USDC;
        markets[1] = GM_TOKEN_ETH_WETH_USDC;

        address[] memory tokens = new address[](2);
        tokens[0] = WETH;
        tokens[1] = USDC;
        exchangeRouter.claimFundingFees(markets, tokens, address(this));
    }
}
