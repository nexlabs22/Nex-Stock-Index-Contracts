import { ethers, upgrades } from "hardhat";
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactoryProcessor = await ethers.getContractFactory("IndexFactoryProcessor");
  console.log('Deploying IndexFactoryProcessor...');

  const indexFactoryProcessor = await upgrades.deployProxy(IndexFactoryProcessor, [
      IndexFactoryStorageAddresses[`sepolia`]
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `indexFactory deployed: ${ await indexFactoryProcessor.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});