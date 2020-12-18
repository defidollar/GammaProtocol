/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import {IZeroXExchange} from "../interfaces/ZeroXExchangeInterface.sol";
import {ERC20Interface} from "../interfaces/ERC20Interface.sol";
import {SafeERC20} from "../packages/oz/SafeERC20.sol";
import {Mock0xERC20Proxy} from "./Mock0xERC20Proxy.sol";

/**
 * @notice Mock 0x Exchange
 */
contract Mock0xExchange {
    using SafeERC20 for ERC20Interface;
    uint256 public called = 0;
    uint256 public takerAmount;
    uint256 public makerAmount;
    bytes public signature;
    uint256 public fillAmount;
    Mock0xERC20Proxy public proxy;

    constructor() public {
        proxy = new Mock0xERC20Proxy();
    }

    function fillOrder(
        IZeroXExchange.Order memory _order,
        uint256 _takerAssetFillAmount,
        bytes memory _signature
    ) external payable returns (IZeroXExchange.FillResults memory fillResults) {
        takerAmount = _order.takerAssetAmount;
        makerAmount = _order.makerAssetAmount;
        signature = _signature;
        fillAmount = _takerAssetFillAmount;
        return IZeroXExchange.FillResults(0, 0, 0, 0, 0);
    }
}
