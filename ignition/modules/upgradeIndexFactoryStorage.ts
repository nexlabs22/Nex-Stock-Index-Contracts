
// import { ethers, upgrades } from "hardhat";
const { ethers, upgrades, network, hre } = require('hardhat');
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, IndexFactoryAddresses, IndexFactoryStorageAddresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

async function deployFactory() {
  
  const [deployer] = await ethers.getSigners();
  // console.log(deployer.address);
  // return;
  const IndexFactoryStorage = await ethers.getContractFactory("IndexFactoryStorage");
  console.log('Upgrading...');
  
  const indexFactoryStorage = await upgrades.upgradeProxy(IndexFactoryStorageAddresses["sepolia"], IndexFactoryStorage, [
    OrderProcessorAddresses[`sepolia`],
    Mag7IndexTokenAddresses[`sepolia`],
    NexVaultAddresses[`sepolia`],
    UsdcAddresses[`sepolia`],
    '6',
    LINKAddresses[`sepolia`],
    ApiOracleAddresses[`goerli`],
    ExternalJobIdBytes32Addresses[`goerli`],
    false
  ], { initializer: 'initialize' }, {gasLimit: 6000000});

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