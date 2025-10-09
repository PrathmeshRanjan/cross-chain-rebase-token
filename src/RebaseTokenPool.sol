// SPDX-License-Identifier: MIT

// Inside each contract, library or interface, use the following order:
// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RebaseToken} from "./RebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowList, address _rmnProxy, address _router)
        TokenPool(_token, _allowList, _rmnProxy, _router)
    {}

    /// @notice Lock tokens into the pool or burn the tokens.
    /// @param lockOrBurnIn Encoded data fields for the processing of tokens on the source chain.
    /// @return lockOrBurnOut Encoded data fields for the processing of tokens on the destination chain.
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);
        // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)
        uint256 userInterestRate = RebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        //uint256 currentInterestRate = IRebaseToken(address(i_token)).getInterestRate();
        RebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // encode a function call to pass the caller's info to the destination pool and update it
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /// @notice Releases or mints tokens to the receiver address.
    /// @param releaseOrMintIn All data required to release or mint tokens.
    /// @return releaseOrMintOut The amount of tokens released or minted on the local chain, denominated
    /// in the local token's decimals.
    /// @dev The offramp asserts that the balanceOf of the receiver has been incremented by exactly the number
    /// of tokens that is returned in ReleaseOrMintOutV1.destinationAmount. If the amounts do not match, the tx reverts.
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;
        (uint256 userInterestRate) = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        // Mint rebasing tokens to the receiver on the destination chain
        // This will also mint any interest that has accrued since the last time the user's balance was updated.
        RebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
