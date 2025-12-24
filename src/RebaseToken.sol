//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Shivang Kumar Nayak
 * @notice This is a cross chain rebase token than incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_InterestRate = (5 * PRECISION_FACTOR) / 1e8; // 0.00005% per second ~ 4.32% per day;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userlastUpdatedTimeStamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        // grant the mint and burn role to the account
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }
    /**
     * @notice Sets the new interest rate in the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // set the interest rate only if it is decreasing
        if (_newInterestRate >= s_InterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_InterestRate, _newInterestRate);
        }
        s_InterestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of the user (the number of tokens that have actually been minted to the user),not including any interest that has accumulated since the last time they interacted with the protocol
     * @param _user The user to get the principle balance of
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the tokens when they deposit into the vault
     * @param _to The user to mint the tokens to
     * @param _amount The amount of tokens to be minted
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_InterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the tokens when they withdraw from the vault
     * @param _from The user to burn the tokens from
     * @param _amount The amount of tokens to be burned
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice calculate the balance for the user including the interest that has accumulated since the last update
     * (principle balance ) + some interest that has accumulated since the last update
     * @param _user The user to find the balance for
     * @return The balance for the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer the tokens from one user to another
     * @param _recepient The user to transfer the tokens to
     * @param _amount The amount of tokens to be transferred
     * @return bool true if the transfer was successful
     */
    function transfer(address _recepient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_recepient);
        _mintAccruedInterest(msg.sender);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recepient) == 0) {
            s_userInterestRate[_recepient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recepient, _amount);
    }

    /**
     * @notice Transfer the tokens from one user to another
     * @param _sender The user to transfer the tokens from
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to be transferred
     * @return bool true if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_recipient);
        _mintAccruedInterest(_sender);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculate the interest that has accumulated since the last update for the user
     * @param _user  The user to calculate the interest accumullated for
     * @return linearInterest The interest rate that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. Calculate the time since the last update
        // 2. Calculate the amount of linear growth
        // (principle amount ) + (principle amount * user interest rate * time elapsed)
        uint256 timeElapsed = block.timestamp - s_userlastUpdatedTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + s_userInterestRate[_user] * timeElapsed;
    }

    /**
     *
     * @notice Mint the accurued interest to the user since the last time they interacted with the protocol (e.g mint, burn, transfer)
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find the current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPricipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest ->balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) -(1)
        uint256 balanceIncrease = currentBalance - previousPricipleBalance;
        // set the user's last updated timestamp
        s_userlastUpdatedTimeStamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the current interest rate that is currently set in the contract. Any future depositers will receive this interest rate
     * @return The current interest rate in the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_InterestRate;
    }

    /**
     * @notice Get the interest rate for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
