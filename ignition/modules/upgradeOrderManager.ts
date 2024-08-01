
// import { ethers, upgrades } from "hardhat";
const { ethers, upgrades, network, hre } = require('hardhat');
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryAddresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

async function deployFactory() {
  
  const [deployer] = await ethers.getSigners();

  const OrderManager = await ethers.getContractFactory("OrderManager");
  console.log('Upgrading...');
  
  const orderManager = await upgrades.upgradeProxy(OrderManagerAddresses["sepolia"], OrderManager, [
    UsdcAddresses[`sepolia`],
    '6',
    OrderProcessorAddresses[`sepolia`]
  ], { initializer: 'initialize' });

  console.log('orderManager upgraded.', orderManager.target)

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployFactory().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});