#!/bin/bash

# Cross-Chain Rebase Token - Complete Deployment and Bridge Script
# Deploys on Ethereum Sepolia and Base Sepolia, then bridges tokens

set -e  # Exit on error

# Load environment variables
source .env

# Configuration
ACCOUNT_NAME="updraft"
DEPOSIT_AMOUNT=100000000000000000  # 0.1 ETH in wei
BRIDGE_AMOUNT=50000000000000000    # 0.05 ETH worth of tokens to bridge (half of deposit)

# Chain Selectors
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
BASE_SEPOLIA_CHAIN_SELECTOR="10344971235874465080"

# CCIP Router Addresses
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
BASE_SEPOLIA_ROUTER="0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93"

# CCIP RMN Proxy Addresses
SEPOLIA_RMN_PROXY="0xba3f6251de62ead5a2ebd3a0c24d1889a70f096e"
BASE_SEPOLIA_RMN_PROXY="0xf0607b56f5f6a77e6b45b1a5d37edaeeb0e5ecf6"

# Registry Module Owner Custom Addresses
SEPOLIA_REGISTRY_MODULE="0xD3c20Eb8Cf02ac3FE50dC8e6C07c7C49A315a3a5"
BASE_SEPOLIA_REGISTRY_MODULE="0xD3c20Eb8Cf02ac3FE50dC8e6C07c7C49A315a3a5"

# Token Admin Registry Addresses
SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
BASE_SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"

# LINK Token Addresses
SEPOLIA_LINK="0x779877A7B0D9E8603169DdbD7836e478b4624789"
BASE_SEPOLIA_LINK="0xE4aB69C077896252FAFBD49EFD26B5D171A32410"

echo "═══════════════════════════════════════════════════════════════"
echo "  Cross-Chain Rebase Token - Deployment & Bridge Script"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get deployer address
DEPLOYER_ADDRESS=$(cast wallet address --account $ACCOUNT_NAME)
echo "Deployer Address: $DEPLOYER_ADDRESS"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: Deploy on Ethereum Sepolia
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 1: Deploying on Ethereum Sepolia"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Deploying RebaseToken and TokenPool on Sepolia..."
output=$(forge script script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${SEPOLIA_RPC_URL} --account $ACCOUNT_NAME --broadcast)

# Extract the addresses from the output
SEPOLIA_TOKEN=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Sepolia RebaseToken deployed at: $SEPOLIA_TOKEN"
echo "Sepolia TokenPool deployed at: $SEPOLIA_POOL"
echo ""

echo "Deploying Vault on Sepolia..."
vault_output=$(forge script script/Deployer.s.sol:VaultDeployer --rpc-url ${SEPOLIA_RPC_URL} --account $ACCOUNT_NAME --broadcast --sig "run(address)" ${SEPOLIA_TOKEN})
SEPOLIA_VAULT=$(echo "$vault_output" | grep -oE '0x[a-fA-F0-9]{40}' | tail -1)
echo "Sepolia Vault deployed at: $SEPOLIA_VAULT"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 2: Deploy on Base Sepolia
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 2: Deploying on Base Sepolia"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Deploying RebaseToken and TokenPool on Base Sepolia..."
output=$(forge script script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${BASE_SEPOLIA_RPC_URL} --account $ACCOUNT_NAME --broadcast)

# Extract the addresses from the output
BASE_TOKEN=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
BASE_POOL=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Base Sepolia RebaseToken deployed at: $BASE_TOKEN"
echo "Base Sepolia TokenPool deployed at: $BASE_POOL"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 3: Configure Token Pools for Cross-Chain Communication
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 3: Configuring Token Pools"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Configuring Sepolia Pool (Sepolia → Base)..."
forge script script/ConfigurePool.s.sol:ConfigurePoolScript \
    --sig "run(address,uint64,address,address)" \
    $SEPOLIA_POOL \
    $BASE_SEPOLIA_CHAIN_SELECTOR \
    $BASE_POOL \
    $BASE_TOKEN \
    --rpc-url $SEPOLIA_RPC_URL \
    --account $ACCOUNT_NAME \
    --broadcast
echo "Sepolia Pool configured"
echo ""

echo "Configuring Base Pool (Base → Sepolia)..."
forge script script/ConfigurePool.s.sol:ConfigurePoolScript \
    --sig "run(address,uint64,address,address)" \
    $BASE_POOL \
    $SEPOLIA_CHAIN_SELECTOR \
    $SEPOLIA_POOL \
    $SEPOLIA_TOKEN \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --account $ACCOUNT_NAME \
    --broadcast
echo "Base Pool configured"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 4: Deposit ETH into Vault
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 4: Depositing ETH into Vault"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Depositing 0.1 ETH into Sepolia Vault..."
cast send ${SEPOLIA_VAULT} "deposit()" --value ${DEPOSIT_AMOUNT} --rpc-url ${SEPOLIA_RPC_URL} --account $ACCOUNT_NAME
echo "Deposit successful"
echo ""

# Wait a bit for interest to accrue
echo "Waiting 10 seconds for interest to accrue..."
sleep 10
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 5: Bridge Tokens from Sepolia to Base
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 5: Bridging Tokens"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Checking balance before bridging..."
SEPOLIA_BALANCE_BEFORE=$(cast balance $(cast wallet address --account $ACCOUNT_NAME) --erc20 ${SEPOLIA_TOKEN} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance before bridging: $SEPOLIA_BALANCE_BEFORE"
echo ""

echo "Bridging tokens from Sepolia to Base..."
forge script script/BridgeTokens.s.sol:BridgeTokensScript \
    --rpc-url ${SEPOLIA_RPC_URL} \
    --account $ACCOUNT_NAME \
    --broadcast \
    --sig "run(address,uint64,address,uint256,address,address)" \
    $(cast wallet address --account $ACCOUNT_NAME) \
    ${BASE_SEPOLIA_CHAIN_SELECTOR} \
    ${SEPOLIA_TOKEN} \
    ${BRIDGE_AMOUNT} \
    ${SEPOLIA_LINK} \
    ${SEPOLIA_ROUTER}
echo "Bridge transaction submitted"
echo ""

SEPOLIA_BALANCE_AFTER=$(cast balance $(cast wallet address --account $ACCOUNT_NAME) --erc20 ${SEPOLIA_TOKEN} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance after bridging: $SEPOLIA_BALANCE_AFTER"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 6: Wait and Verify
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  STEP 6: Waiting for CCIP Delivery"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Waiting 2 minutes for CCIP message to be delivered..."
sleep 120
echo "Wait complete"
echo ""

# Check balances on both chains
echo "═══════════════════════════════════════════════════════════════"
echo "  Final Balances"
echo "═══════════════════════════════════════════════════════════════"
echo ""

SEPOLIA_FINAL_BALANCE=$(cast balance $(cast wallet address --account $ACCOUNT_NAME) --erc20 ${SEPOLIA_TOKEN} --rpc-url ${SEPOLIA_RPC_URL})
BASE_FINAL_BALANCE=$(cast balance $(cast wallet address --account $ACCOUNT_NAME) --erc20 ${BASE_TOKEN} --rpc-url ${BASE_SEPOLIA_RPC_URL})

echo "Sepolia Chain:"
echo "  Token Balance: $SEPOLIA_FINAL_BALANCE"
echo "  Token Address: $SEPOLIA_TOKEN"
echo "  Pool Address: $SEPOLIA_POOL"
echo "  Vault Address: $SEPOLIA_VAULT"
echo ""

echo "Base Sepolia Chain:"
echo "  Token Balance: $BASE_FINAL_BALANCE"
echo "  Token Address: $BASE_TOKEN"
echo "  Pool Address: $BASE_POOL"
echo ""

# Check interest rate preservation
BASE_INTEREST_RATE=$(cast call $BASE_TOKEN "getUserInterestRate(address)(uint256)" $(cast wallet address --account $ACCOUNT_NAME) --rpc-url ${BASE_SEPOLIA_RPC_URL})
SEPOLIA_INTEREST_RATE=$(cast call $SEPOLIA_TOKEN "getUserInterestRate(address)(uint256)" $(cast wallet address --account $ACCOUNT_NAME) --rpc-url ${SEPOLIA_RPC_URL})

echo "Interest Rates:"
echo "  Sepolia: $SEPOLIA_INTEREST_RATE"
echo "  Base: $BASE_INTEREST_RATE"
echo ""

if [ "$BASE_INTEREST_RATE" = "$SEPOLIA_INTEREST_RATE" ]; then
    echo "✓ SUCCESS! Interest rates match across chains!"
else
    echo "⚠ Warning: Interest rates don't match"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  Deployment Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "Ethereum Sepolia:"
echo "  RebaseToken: $SEPOLIA_TOKEN"
echo "  TokenPool: $SEPOLIA_POOL"
echo "  Vault: $SEPOLIA_VAULT"
echo ""

echo "Base Sepolia:"
echo "  RebaseToken: $BASE_TOKEN"
echo "  TokenPool: $BASE_POOL"
echo ""

echo "✓ Script completed successfully!"
echo ""

# Save deployment info to file
cat > deployment-info.txt << EOF
Cross-Chain Rebase Token Deployment
Generated: $(date)

Ethereum Sepolia:
  RebaseToken: $SEPOLIA_TOKEN
  TokenPool: $SEPOLIA_POOL
  Vault: $SEPOLIA_VAULT
  Chain Selector: $SEPOLIA_CHAIN_SELECTOR

Base Sepolia:
  RebaseToken: $BASE_TOKEN
  TokenPool: $BASE_POOL
  Chain Selector: $BASE_SEPOLIA_CHAIN_SELECTOR

Deployer Address: $DEPLOYER_ADDRESS
Deposit Amount: 0.1 ETH
Bridge Amount: 0.05 ETH
EOF

echo "Deployment info saved to deployment-info.txt"
