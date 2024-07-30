import { ethers } from "hardhat";
// import {
//     abi as Factory_ABI,
//     bytecode as Factory_BYTECODE,
//   } from '../artifacts/contracts/factory/IndexFactory.sol/IndexFactory.json'
import {
    abi as FactoryStorage_ABI,
    bytecode as FactoryStorage_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactoryStorage.sol/IndexFactoryStorage.json'
import { dShares, IndexFactoryStorageAddresses } from "../../../contractAddresses";
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
    const result = await contract.connect(deployer).mockFillAssetsList(
        [
        dShares[0], //apple 20
        dShares[2], //meta 7
        dShares[3], //amazon 12
        dShares[5], //nvidia 20
        dShares[15],// advanced micro devices 22
        dShares[21],// blockInch 14
        dShares[39], //reddit 5
        ],
        [
        "20000000000000000000", 
        "7000000000000000000",
        "12000000000000000000",
        "20000000000000000000",
        "22000000000000000000",
        "14000000000000000000",
        "5000000000000000000",
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