import { createPublicClient, createWalletClient, http, Log, publicActions } from 'viem'
import { mainnet, sepolia } from 'viem/chains'
require("dotenv").config()
import {
    abi as Counter_ABI,
    bytecode as Counter_BYTECODE,
  } from '../../../artifacts/contracts/test/Counter.sol/Counter.json'
import {
abi as Token_ABI,
bytecode as Token_BYTECODE,
} from '../../../artifacts/contracts/test/Token.sol/Token.json'
import { UsdcAddresses } from '../../../contractAddresses'
import { privateKeyToAccount } from 'viem/accounts'
// import { Event } from '../../../typechain-types/contracts/factory/TestIndexFactory';
// import {}

const account = privateKeyToAccount(`0x${process.env.PRIVATE_KEY}` as `0x${string}`) 

const client = createWalletClient({ 
    account,
    chain: sepolia, 
    transport: http(process.env.ETHEREUM_SEPOLIA_RPC_URL), 
  }).extend(publicActions) 




// async function main(){
// const blockNumber = await client.getBlockNumber()
// console.log(blockNumber)
// }
// main()

async function execution(logs: any) {
    // console.log(logs);
    // console.log(logs[0]?.args?.from)
    console.log("Increasing...")
    const { request } = await client.simulateContract({
        account,
        address: "0x007F64Ad841C4Bc26E290b2137eD8374466A1359", //counter address
        abi: Counter_ABI,
        functionName: 'increaseNumber',
        // args: ["0xe98A6145acF43Fa2f159B28C70eB036A5Dc69409", 1000000n]
      }) // Public Action
    const hash = await client.writeContract(request) // Wallet Action
    console.log("increased !")
}

const unwatch = client.watchContractEvent({
    address: UsdcAddresses[`sepolia`] as `0x${string}`,
    abi: Token_ABI,
    eventName: 'Transfer', 
    // args: { from: '0xc961145a54C96E3aE9bAA048c4F4D6b04C13916b' }, 
    onLogs: logs => execution(logs)
  })