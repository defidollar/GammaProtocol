/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity =0.6.10;

pragma experimental ABIEncoderV2;

import {ERC20Initializable} from "../packages/oz/upgradeability/ERC20Initializable.sol";
import {SafeMath} from "../packages/oz/SafeMath.sol";
import {SafeERC20} from "../packages/oz/SafeERC20.sol";
import {OtokenInterface} from "../interfaces/OtokenInterface.sol";
import {ERC20Interface} from "../interfaces/ERC20Interface.sol";
import {Actions} from "../libs/Actions.sol";
import {FixedPointInt256 as FPI} from "../libs/FixedPointInt256.sol";

contract Opeth is ERC20Initializable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Interface;
    using FPI for FPI.FixedPointInt;

    uint256 internal constant BASE = 8;

    ControllerInterface public controller;
    OtokenInterface public oToken;
    ERC20Interface public underlyingAsset;
    ERC20Interface public collateralAsset;
    bool public proceedsClaimed;
    uint256 public unitPayout;

    function init(address _controller, address _oToken) external initializer {
        controller = ControllerInterface(_controller);
        oToken = OtokenInterface(_oToken);
        underlyingAsset = ERC20Interface(oToken.underlyingAsset());
        collateralAsset = ERC20Interface(oToken.collateralAsset());
    }

    function mint(uint256 amount) external {
        require(now < oToken.expiryTimestamp(), "Opeth: oToken is expired");
        ERC20Interface(address(oToken)).safeTransferFrom(msg.sender, address(this), amount);
        underlyingAsset.safeTransferFrom(msg.sender, address(this), oTokenToUnderlyingAssetAmount(amount, false));
        _mint(msg.sender, amount);
    }

    function redeem(uint256 amount) external {
        _burn(msg.sender, amount);
        if (!proceedsClaimed) {
            claimProceeds(); // will revert if !oToken.isSettlementAllowed()
        }
        uint256 payout = unitPayout.mul(amount).div(10**BASE);
        if (payout > 0) {
            collateralAsset.safeTransfer(msg.sender, payout);
        }
        underlyingAsset.safeTransfer(msg.sender, oTokenToUnderlyingAssetAmount(amount, true));
    }

    function oTokenToUnderlyingAssetAmount(uint256 amount, bool _roundDown) public view returns (uint256) {
        return FPI.fromScaledUint(amount, BASE).toScaledUint(uint256(underlyingAsset.decimals()), _roundDown);
    }

    function claimProceeds() public {
        Actions.ActionArgs[] memory _actions = new Actions.ActionArgs[](1);
        _actions[0].actionType = Actions.ActionType.Redeem;
        _actions[0].secondAddress = address(this);
        uint256 collateralBefore = collateralAsset.balanceOf(address(this));
        controller.operate(_actions);
        uint256 collateralNow = collateralAsset.balanceOf(address(this));
        unitPayout = collateralNow.sub(collateralBefore).mul(10**BASE).div(totalSupply());
        proceedsClaimed = true;
    }
}

interface ControllerInterface {
    function operate(Actions.ActionArgs[] memory _actions) external;
}
