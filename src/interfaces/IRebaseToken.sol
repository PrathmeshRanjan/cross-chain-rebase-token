// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRebaseToken
 * @author Prathmesh Ranjan
 * @notice Interface for the RebaseToken contract
 * @dev This interface extends IERC20 and adds rebase-specific functionality
 */
interface IRebaseToken is IERC20 {
    ///////////////////
    //// EVENTS ///////
    ///////////////////

    /**
     * @notice Emitted when the global interest rate is updated
     * @param newInterestRate The new interest rate set
     */
    event InterestRateSet(uint256 newInterestRate);

    ///////////////////
    //// ERRORS ///////
    ///////////////////

    /**
     * @notice Thrown when attempting to set an interest rate that is equal to or higher than the current rate
     * @param interestRate The invalid interest rate that was attempted to be set
     */
    error RebaseToken__NewInterestRateCannotBeEqualOrHigher(uint256 interestRate);

    /////////////////////////////////////
    //// EXTERNAL & PUBLIC FUNCTIONS ////
    /////////////////////////////////////

    /**
     * @notice Grants the MINT_AND_BURN_ROLE to an account
     * @param _account The address to grant the role to
     * @dev Only callable by the contract owner
     */
    function grantMintAndBurnRole(address _account) external;

    /**
     * @notice Sets the global interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease, never increase
     * @dev Only callable by the contract owner
     */
    function setInterestRate(uint256 _newInterestRate) external;

    /**
     * @notice Mints new tokens for a given address with a specific interest rate
     * @param _to The address to mint the tokens to
     * @param _amount The number of tokens to mint
     * @param _userInterestRate The interest rate to set for the user
     * @dev Only callable by addresses with MINT_AND_BURN_ROLE
     * @dev This function increases the total supply and sets the user's interest rate
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external;

    /**
     * @notice Burns tokens from a specified address
     * @param _from The address to burn the tokens from
     * @param _amount The number of tokens to be burned (use type(uint256).max to burn all)
     * @dev Only callable by addresses with MINT_AND_BURN_ROLE
     * @dev This function decreases the total supply
     */
    function burn(address _from, uint256 _amount) external;

    /////////////////////////
    //// VIEW FUNCTIONS /////
    /////////////////////////

    /**
     * @notice Returns the interest rate of a specific user
     * @param _user The address of the user
     * @return The user's locked-in interest rate
     */
    function getUserInterestRate(address _user) external view returns (uint256);

    /**
     * @notice Returns the principal balance of a user
     * @param _user The address of the user
     * @return The principal balance (without accrued interest)
     * @dev This is the stored balance that does not include perpetually accruing interest
     */
    function getPrincipalBalanceOfUser(address _user) external view returns (uint256);

    /**
     * @notice Returns the current global interest rate of the token
     * @return The global interest rate
     */
    function getCurrentInterestRate() external view returns (uint256);
}
