// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRebaseToken} from "./Interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a mint function that mints tokens to the user equal to the amount of ETH the user sent
    // create a redeem function that burns tokens from the user and sends the user eth
    // create a way to add rewards to the vault
    IRebaseToken private immutable i_rebaseToken;

    event Deposited(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and mint rebase tokens in return to the user
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Get the address of the rebase token contract
     * @return The address of the rebase token contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    /**
     * @notice Redeem rebase tokens from the vault and burn them to get ETH in return
     * @param _amount The amount of rebase tokens to redeem
     */
    function redeem(uint256 _amount) external {
        // burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // send the user eth equal to the amount of tokens burned
        (bool success,) = payable(msg.sender).call{value: _amount}("");

        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }
}
