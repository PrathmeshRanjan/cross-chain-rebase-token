// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
// import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {Test, console} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";

contract CrossChainTest is Test {
    RebaseToken ethRebaseToken;
    RebaseToken arbRebaseToken;

    Vault vault;

    RebaseTokenPool ethRebaseTokenPool;
    RebaseTokenPool arbRebaseTokenPool;

    // IRebaseToken iEthRebaseToken;
    // IRebaseToken iArbRebaseToken;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    Register.NetworkDetails ethNetworkDetails;
    Register.NetworkDetails arbNetworkDetails;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() external {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deployement and configuration on Ethereum Sepolia
        ethNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        ethRebaseToken = new RebaseToken();
        vault = new Vault(ethRebaseToken);
        ethRebaseToken.grantMintAndBurnRole(address(vault));
        ethRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(ethRebaseToken)),
            new address[](0),
            ethNetworkDetails.rmnProxyAddress,
            ethNetworkDetails.routerAddress
        );
        ethRebaseToken.grantMintAndBurnRole(address(ethRebaseTokenPool));
        RegistryModuleOwnerCustom(ethNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(ethRebaseToken)
        );
        TokenAdminRegistry(ethNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethRebaseToken));
        TokenAdminRegistry(ethNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(ethRebaseToken), address(ethRebaseTokenPool)
        );
        vm.stopPrank();

        // 2. Deployement and configuration on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbRebaseToken = new RebaseToken();
        arbRebaseToken.grantMintAndBurnRole(address(vault));
        arbRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(arbRebaseToken)),
            new address[](0),
            arbNetworkDetails.rmnProxyAddress,
            arbNetworkDetails.routerAddress
        );
        arbRebaseToken.grantMintAndBurnRole(address(arbRebaseTokenPool));
        RegistryModuleOwnerCustom(arbNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbRebaseToken)
        );
        TokenAdminRegistry(arbNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbRebaseToken));
        TokenAdminRegistry(arbNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbRebaseToken), address(arbRebaseTokenPool)
        );

        configureTokenPool(
            sepoliaFork,
            address(ethRebaseTokenPool),
            arbNetworkDetails.chainSelector,
            address(arbRebaseTokenPool),
            address(arbRebaseToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbRebaseTokenPool),
            ethNetworkDetails.chainSelector,
            address(ethRebaseTokenPool),
            address(ethRebaseToken)
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }
}
