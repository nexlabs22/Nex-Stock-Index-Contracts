import { ethers, upgrades } from "hardhat";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const NexVault = await ethers.getContractFactory("NexVault");
  console.log('Deploying NexVault...');

  const nexVault = await upgrades.deployProxy(NexVault, [
      "0x0000000000000000000000000000000000000000"
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `indexToken deployed: ${ await nexVault.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});