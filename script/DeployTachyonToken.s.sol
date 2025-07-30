// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/TachyonToken.sol";

// @title DeployTachyonToken
// @notice Deploys TachyonToken via UUPS proxy for upgradability, targeting Base Sepolia or mainnet.
// @dev Follows Consensys best practices: uses UUPS proxy pattern for upgradability with owner control.
//      UUPS pattern provides gas-efficient upgrades controlled by the implementation contract.
//      Assumes .env with PRIVATE_KEY and BASE_SEPOLIA_RPC_URL set.
contract DeployTachyonToken is Script {
    function run() external {
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the actual deployer address
        address deployer = vm.addr(deployerPrivateKey);

        // Deploy implementation contract (UUPS-compatible)
        TachyonToken implementation = new TachyonToken();
        console.log("TachyonToken Implementation deployed at:", address(implementation));

        // Encode initializer data for UUPS proxy
        address initialOwner = deployer; // Use actual deployer address
        bytes memory initializerData = abi.encodeWithSelector(
            TachyonToken.initialize.selector,
            initialOwner
        );

        // Deploy ERC1967Proxy (UUPS-compatible proxy)
        // This is the correct proxy type for UUPS upgradeable contracts
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initializerData
        );
        console.log("TachyonToken Proxy deployed at:", address(proxy));

        // Verify proxy initialization and upgradability
        TachyonToken token = TachyonToken(payable(address(proxy)));
        console.log("Token initialized with name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Total supply:", token.totalSupply());
        console.log("Decimals:", token.decimals());
        console.log("Initial owner:", token.owner());
        
        // Verify UUPS upgradeability is working
        try token.proxiableUUID() returns (bytes32 uuid) {
            console.log("UUPS UUID (hex):", vm.toString(uuid));
        } catch {
            console.log("Warning: UUPS interface not accessible");
        }

        vm.stopBroadcast();
    }
}