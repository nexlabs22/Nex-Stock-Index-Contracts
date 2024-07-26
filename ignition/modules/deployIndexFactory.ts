import { ethers, upgrades } from "hardhat";
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const IndexFactory = await ethers.getContractFactory("IndexFactory");
  console.log('Deploying IndexFactory...');

  const indexFactory = await upgrades.deployProxy(IndexFactory, [
      OrderProcessorAddresses[`sepolia`],
      Mag7IndexTokenAddresses[`sepolia`],
      NexVaultAddresses[`sepolia`],
      UsdcAddresses[`sepolia`],
      '6',
      LINKAddresses[`sepolia`],
      ApiOracleAddresses[`goerli`],
      ExternalJobIdBytes32Addresses[`goerli`],
      false
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `indexFactory deployed: ${ await indexFactory.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});