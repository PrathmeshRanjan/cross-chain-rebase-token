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
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

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

    uint256 public SEND_VALUE = 1e5;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() external {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deployment and configuration on Ethereum Sepolia
        vm.selectFork(sepoliaFork);
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

        // 2. Deployment and configuration on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);
        arbRebaseToken = new RebaseToken();
        // Note: Vault only exists on Sepolia, not on Arbitrum

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
        vm.stopPrank();

        // 3. Configure token pools for cross-chain communication
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        configureTokenPool(
            address(ethRebaseTokenPool),
            arbNetworkDetails.chainSelector,
            address(arbRebaseTokenPool),
            address(arbRebaseToken)
        );
        vm.stopPrank();

        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        configureTokenPool(
            address(arbRebaseTokenPool),
            ethNetworkDetails.chainSelector,
            address(ethRebaseTokenPool),
            address(ethRebaseToken)
        );
        vm.stopPrank();

        // Return to Sepolia fork for tests
        vm.selectFork(sepoliaFork);
    }

    function configureTokenPool(address localPool, uint64 remoteChainSelector, address remotePool, address remoteToken)
        internal
    {
        // Fork should already be selected before calling this
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

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);
        vm.startPrank(user);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: "", // We don't need any extra args for this example
            feeToken: localNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Approve the fee
        // log the values before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(user);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance before bridge: %d", initialArbBalance);
        vm.selectFork(localFork); // in the latest version of chainlink-local, it assumes you are currently on the local fork before calling switchChainAndRouteMessage
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        console.log("Remote user interest rate: %d", remoteToken.getUserInterestRate(user));
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(user);
        console.log("Remote balance after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    function testBridgeAllTokens() external {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();
        assertEq(ethRebaseToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            ethNetworkDetails,
            arbNetworkDetails,
            ethRebaseToken,
            arbRebaseToken
        );
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(
            arbRebaseToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbNetworkDetails,
            ethNetworkDetails,
            arbRebaseToken,
            ethRebaseToken
        );
    }
}
