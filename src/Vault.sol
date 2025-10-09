// SPDX-License-Identifier: MIT

// Inside each contract, library or interface, use the following order:
// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions

pragma solidity ^0.8.24;

import {RebaseToken} from "./RebaseToken.sol";

contract Vault {
    RebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 depositAmount);
    event Redeem(address indexed user, uint256 redeemAmount);

    error Vault__RedeemFailed();

    constructor(RebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @dev Allows users to deposit ETH into the vault and mint rebase tokens in return
     */
    function deposit() external payable {
        uint256 userInterestRate = i_rebaseToken.getUserInterestRate(msg.sender);
        i_rebaseToken.mint(msg.sender, msg.value, userInterestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Redeems rebase token for the underlying asset
     * @param _amount the amount being redeemed
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender); // This is done to clear token dust
        }
        // 1. Burn the tokens of the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Send the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
