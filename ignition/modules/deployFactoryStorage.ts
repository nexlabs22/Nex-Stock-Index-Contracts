import { ethers, upgrades } from "hardhat";
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactoryStorage = await ethers.getContractFactory("IndexFactoryStorage");
  console.log('Deploying IndexFactoryStorage...');

  const indexFactoryStorage = await upgrades.deployProxy(IndexFactoryStorage, [
      OrderProcessorAddresses[`sepolia`],
      Mag7IndexTokenAddresses[`sepolia`],
      NexVaultAddresses[`sepolia`],
      UsdcAddresses[`sepolia`],
      '6',
      LINKAddresses[`sepolia`],
      ApiOracleAddresses[`goerli`],
      ExternalJobIdBytes32Addresses[`goerli`]
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `indexFactoryStorage deployed: ${ await indexFactoryStorage.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});