//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


/**
 * @title Rebase Token
 * @author Shivang Kumar Nayak
 * @notice This is a cross chain rebase token than incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20{
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_InterestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userlastUpdatedTimeStamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20 ("Rebase Token" , "RBT"){}
    /**
     * @notice Sets the new interest rate in the contract.
     * @param _newInterestRate The new interest rate to set.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _newInterestRate) external{
        // set the interest rate only if it is decreasing
        if(_newInterestRate >= s_InterestRate){
            revert RebaseToken__InterestRateCanOnlyDecrease(s_InterestRate, _newInterestRate);
        }
        s_InterestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }


    /**
     * @notice Mint the tokens when they deposit into the vault
     * @param _to The user to mint the tokens to
     * @param _amount The amount of tokens to be minted
     */
    function mint(address _to , uint256 _amount) external{
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_InterestRate;
        _mint(_to,_amount);
    }

    /**
     * @notice calculate the balance for the user including the interest that has accumulated since the last update 
     *(principle balance ) + some interest that has accumulated since the last update
     * @param _user The user to find the balance for
     * @return The balance for the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns(uint256){
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)/PRECISION_FACTOR;
    }

    /**
     * @notice calculate the interest that has accumulated since the last update for the user
     * @param _user  The user to calculate the interest accumullated for
     * @return linearInterest The interest rate that has accumulated since the last update
     */

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view  returns(uint256 linearInterest){
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. Calculate the time since the last update
        // 2. Calculate the amount of linear growth
        // (principle amount ) + (principle amount * user interest rate * time elapsed)
        uint256 timeElapsed = block.timestamp - s_userlastUpdatedTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + s_userInterestRate[_user] * timeElapsed;
    }

    function _mintAccruedInterest(address _user) internal{
        // (1) find the current balance of rebase tokens that have been minted to the user -> principle balance
        // (2) calculate their current balance including any interest ->balanceOf
        // calculate the number of tokens that need to be minted to the user -> (2) -(1) 
        // call _mint to mint the tokens to the user
        // set the user's last updated timestamp
        s_userlastUpdatedTimeStamp[_user] = block.timestamp;
    }

    /**
     * @notice Get the interest rate for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user)external view returns(uint256){
        return s_userInterestRate[_user];
    }
}
