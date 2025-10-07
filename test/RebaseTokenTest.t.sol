// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Test} from "forge-std/Test.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(rebaseToken);
        rebaseToken.grantMintAndBurnRole(address(vault));
        payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e4, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.stopPrank();
    }
}
