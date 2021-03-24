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

/**
 * @title Opeth
 * @notice Contract that let's one enter tokenized hedged positions
 */
contract Opeth is ERC20Initializable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Interface;
    using FPI for FPI.FixedPointInt;

    ControllerInterface public controller;
    OtokenInterface public oToken;
    ERC20Interface public underlyingAsset;
    ERC20Interface public collateralAsset;

    /// @dev Precision for both Otokens and Opeth
    uint256 internal constant BASE = 8;

    /// @dev Whether proceeds have been claimed post dispute period
    bool public proceedsClaimed;

    /// @dev Collateral payout per Opeth token
    uint256 public unitPayout;

    /// @dev Underlying asset precision decimals
    uint256 internal underlyingDecimals;

    /**
     * @notice initalize the deployed contract
     * @param _controller Opyn controller
     * @param _oToken oToken contract address
     */
    function init(address _controller, address _oToken) external initializer {
        require(_controller != address(0), "Opeth: invalid controller address");
        require(_oToken != address(0), "Opeth: invalid oToken address");

        oToken = OtokenInterface(_oToken);
        require(now < oToken.expiryTimestamp(), "Opeth: oToken has expired");

        controller = ControllerInterface(_controller);
        collateralAsset = ERC20Interface(oToken.collateralAsset());
        underlyingAsset = ERC20Interface(oToken.underlyingAsset());
        underlyingDecimals = uint256(underlyingAsset.decimals());
    }

    /**
     * @notice Mint Opeth tokens
     * @param _amount Amount of Opeth to mint and pull oTokens and corresponding amount of underlyingAsset
     */
    function mint(uint256 _amount) external {
        require(now < oToken.expiryTimestamp(), "Opeth: oToken is expired");
        ERC20Interface(address(oToken)).safeTransferFrom(msg.sender, address(this), _amount);
        underlyingAsset.safeTransferFrom(msg.sender, address(this), oTokenToUnderlyingAssetAmount(_amount, true));
        _mint(msg.sender, _amount);
    }

    /**
     * @notice redeem Opeth tokens
     * @param _amount Amount of Opeth to redeem
     */
    function redeem(uint256 _amount) external {
        if (proceedsClaimed) {
            _processPayout(_amount);
        } else if (controller.isSettlementAllowed(address(oToken))) {
            claimProceeds();
            _processPayout(_amount);
        } else {
            // send back vanilla OTokens, because it is not yet time for settlement
            ERC20Interface(address(oToken)).safeTransfer(msg.sender, _amount);
        }
        _burn(msg.sender, _amount);
        underlyingAsset.safeTransfer(msg.sender, oTokenToUnderlyingAssetAmount(_amount, false));
    }

    /**
     * @notice Process collateralAsset payout
     * @param _amount Amount of OTokens to process payout for
     */
    function _processPayout(uint256 _amount) internal {
        uint256 payout = unitPayout.mul(_amount).div(10**BASE);
        if (payout > 0) {
            collateralAsset.safeTransfer(msg.sender, payout);
        }
    }

    /**
     * @notice OToken to underlying asset amount
     * @param _amount Amount of OTokens to determine underlying asset amount for
     */
    function oTokenToUnderlyingAssetAmount(uint256 _amount, bool _roundUp) public view returns (uint256) {
        if (underlyingDecimals >= BASE) {
            return _amount.mul(10**(underlyingDecimals - BASE));
        }
        uint256 amount = _amount.div(10**(BASE - underlyingDecimals));
        if (_roundUp) {
            return amount.add(1);
        }
        return amount;
    }

    /**
     * @notice Redeem OTokens for payout, if any
     */
    function claimProceeds() public {
        Actions.ActionArgs[] memory _actions = new Actions.ActionArgs[](1);
        _actions[0].actionType = Actions.ActionType.Redeem;
        _actions[0].secondAddress = address(this);
        _actions[0].asset = address(oToken);
        _actions[0].amount = ERC20Interface(address(oToken)).balanceOf(address(this));

        uint256 collateralBefore = collateralAsset.balanceOf(address(this));
        controller.operate(_actions);
        uint256 collateralNow = collateralAsset.balanceOf(address(this));
        unitPayout = collateralNow.sub(collateralBefore).mul(10**BASE).div(totalSupply());
        proceedsClaimed = true;
    }

    receive() external payable {
        revert("Cannot receive ETH");
    }

    fallback() external payable {
        revert("Cannot receive ETH");
    }
}

interface ControllerInterface {
    function operate(Actions.ActionArgs[] memory _actions) external;

    function isSettlementAllowed(address _otoken) external view returns (bool);
}
