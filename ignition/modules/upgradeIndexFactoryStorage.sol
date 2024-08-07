
// import { ethers, upgrades } from "hardhat";
const { ethers, upgrades, network, hre } = require('hardhat');
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryAddresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

async function deployFactory() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactoryStorage = await ethers.getContractFactory("IndexFactoryStorage");
  console.log('Upgrading...');
  
  const indexFactoryStorage = await upgrades.upgradeProxy(IndexFactoryAddresses["sepolia"], IndexFactoryStorage, [
      IndexFactoryStorageAddresses[`sepolia`],
      OrderManagerAddresses[`sepolia`],
      OrderProcessorAddresses[`sepolia`],
      Mag7IndexTokenAddresses[`sepolia`],
      NexVaultAddresses[`sepolia`],
      UsdcAddresses[`sepolia`],
      '6',
      false
  ], { initializer: 'initialize' });

  console.log('indexFactoryStorage upgraed.', indexFactoryStorage.target)
//   await indexFactory.waitForDeployment()

//   console.log(
//     `IndexFactory proxy upgraded by:${ await indexFactory.getAddress()}`
//   );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployFactory().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});