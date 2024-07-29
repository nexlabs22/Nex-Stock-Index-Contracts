import { ethers, upgrades } from "hardhat";

//sepoliaCounterAddress = 0x007F64Ad841C4Bc26E290b2137eD8374466A1359

async function deployIndexToken() {
  
  const [deployer] = await ethers.getSigners();

  const Counter = await ethers.getContractFactory("Counter");
  console.log('Deploying Counter...');

  const counter = await upgrades.deployProxy(Counter, [], { initializer: 'initialize' });

//   await orderManager.deployed()

  console.log(
    `counter deployed: ${ await counter.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
deployIndexToken().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});