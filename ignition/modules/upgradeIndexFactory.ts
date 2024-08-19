
// import { ethers, upgrades } from "hardhat";
const { ethers, upgrades, network, hre } = require('hardhat');
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryAddresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

async function deployFactory() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactory = await ethers.getContractFactory("IndexFactory");
  console.log('Upgrading...');
  
  const indexFactory = await upgrades.upgradeProxy(IndexFactoryAddresses["sepolia"], IndexFactory, [
      IndexFactoryStorageAddresses[`sepolia`]
  ], { initializer: 'initialize' });

  console.log('indexFactory upgraed.', indexFactory.target)
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