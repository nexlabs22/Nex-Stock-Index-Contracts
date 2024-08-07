import { ethers, upgrades } from "hardhat";
import { ApiOracleAddresses, ExternalJobIdBytes32Addresses, LINKAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderProcessorAddresses, UsdcAddresses } from "../../contractAddresses";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const OrderManager = await ethers.getContractFactory("OrderManager");
  console.log('Deploying OrderManager...');

  const orderManager = await upgrades.deployProxy(OrderManager, [
      UsdcAddresses[`sepolia`],
      '6',
      OrderProcessorAddresses[`sepolia`]
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `orderManager deployed: ${ await orderManager.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});