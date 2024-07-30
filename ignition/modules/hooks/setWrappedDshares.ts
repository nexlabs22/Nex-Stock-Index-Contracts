import { ethers } from "hardhat";
// import {
//     abi as Factory_ABI,
//     bytecode as Factory_BYTECODE,
//   } from '../artifacts/contracts/factory/IndexFactory.sol/IndexFactory.json'
import {
    abi as FactoryStorage_ABI,
    bytecode as FactoryStorage_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactoryStorage.sol/IndexFactoryStorage.json'
import { dShares, IndexFactoryStorageAddresses, wrappedDshares } from "../../../contractAddresses";
// import { goerliAnfiFactoryAddress } from "../contractAddresses";
require("dotenv").config()

async function main() {
    const [deployer] = await ethers.getSigners();
    const provider = new ethers.JsonRpcProvider(process.env.ETHEREUM_SEPOLIA_RPC_URL)
    const contract:any = new ethers.Contract(
        IndexFactoryStorageAddresses['sepolia'] as string, //factory goerli
        FactoryStorage_ABI,
        provider
    )

    // msft:22 aaple:20 nvda:20 goog:14 amzn:12 meta:7 tesla:5

    // AdvancedMicroDevices:22 aaple:20 nvda:20 blockInch:14 amzn:12 meta:7 reddit:5
    console.log("sending data...")
    const result = await contract.connect(deployer).setWrappedDShareAddresses(
        [
        dShares[0], //apple
        dShares[2], //meta
        dShares[3], //amazon
        dShares[5], //nvidia
        dShares[15],// advanced micro devices
        dShares[21],// blockInch
        dShares[39], //reddit
        ],
        [
        wrappedDshares[0], //apple
        wrappedDshares[2], //meta
        wrappedDshares[3], //amazon
        wrappedDshares[5], //nvidia
        wrappedDshares[15],// advanced micro devices
        wrappedDshares[21],// blockInch
        wrappedDshares[39], //reddit
        ]
    )
    console.log("waiting for results...")
    const receipt = await result.wait();
    if(receipt.status ==1 ){
        console.log("success =>", receipt)
    }else{
        console.log("failed =>", receipt)
    }
}

main()