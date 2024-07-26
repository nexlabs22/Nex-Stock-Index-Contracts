import { ethers, upgrades } from "hardhat";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const IndexToken = await ethers.getContractFactory("IndexToken");
  console.log('Deploying IndexToken...');

  const indexToken = await upgrades.deployProxy(IndexToken, [
      "Magnificent 7",
      "MAG7",
      "1000000000000000000", //fee rate per day
      deployer.address,
      "1000000000000000000000000000" // 1 billion supply ceiling
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `indexToken deployed: ${ await indexToken.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});