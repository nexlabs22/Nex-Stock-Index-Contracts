
// import { ethers, upgrades } from "hardhat";
const { ethers, upgrades, network, hre } = require('hardhat');
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryAddresses, IndexFactoryProcessorAddresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

async function deployFactory() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactoryProcessor = await ethers.getContractFactory("IndexFactoryProcessor");
  console.log('Upgrading...');
  
  const indexFactoryProcessor = await upgrades.upgradeProxy(IndexFactoryProcessorAddresses["sepolia"], IndexFactoryProcessor, [
      IndexFactoryStorageAddresses[`sepolia`]
  ], { initializer: 'initialize' });

  console.log('indexFactoryProcessor upgraed.', indexFactoryProcessor.target)
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