import { ethers, upgrades } from "hardhat";

// sepoliaOrderManager = "0x478CbE6D18d69773EEaf94523125a12Cfd985404"
async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const OrderManager = await ethers.getContractFactory("OrderManager");
  console.log('Deploying OrderManager...');

  const orderManager = await upgrades.deployProxy(OrderManager, [
      "0x709CE4CB4b6c2A03a4f938bA8D198910E44c11ff", //usdc dinary
      "6", // usdc decimals
      "0xd771a71e5bb303da787b4ba2ce559e39dc6ed85c", //apple token
      "0xd0d00Ee8457d79C12B4D7429F59e896F11364247" //issuer (order processor)
  ], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `IndexToken deployed: ${ await orderManager.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});