import { ethers } from "hardhat";

import {
    abi as FactoryStorage_ABI,
    bytecode as FactoryStorage_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactoryStorage.sol/IndexFactoryStorage.json'
import { dShares, IndexFactoryAddresses, IndexFactoryProcessorAddresses, IndexFactoryStorageAddresses, Mag7IndexTokenAddresses, NexVaultAddresses, OrderManagerAddresses, wrappedDshares } from "../../../contractAddresses";
// import { goerliAnfiFactoryAddress } from "../contractAddresses";
require("dotenv").config()

async function main() {

    const [deployer] = await ethers.getSigners();
    const provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_SEPOLIA_RPC_URL)

    const factoryStorageContract:any = new ethers.Contract(
        IndexFactoryStorageAddresses['sepolia'] as string, //factory goerli
        FactoryStorage_ABI,
        provider
    )

    console.log("setting factory ...")
    const result1 = await factoryStorageContract.connect(deployer).setFactory(
        IndexFactoryAddresses['sepolia'] as string
    )
    const receipt1 = await result1.wait();

    console.log("setting factory processor ...")
    const result2 = await factoryStorageContract.connect(deployer).setFactoryProcessor(
        IndexFactoryProcessorAddresses['sepolia'] as string
    )
    const receipt2 = await result2.wait();

    console.log("setting order manager ...")
    const result3 = await factoryStorageContract.connect(deployer).setOrderManager(
        OrderManagerAddresses['sepolia'] as string
    )
    const receipt3 = await result3.wait();

    console.log("setting index token ...")
    const result4 = await factoryStorageContract.connect(deployer).setTokenAddress(
        Mag7IndexTokenAddresses['sepolia'] as string
    )
    const receipt4 = await result4.wait();
    console.log('Ended')
}

main()