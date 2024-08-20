import { createPublicClient, createWalletClient, http, Log, publicActions } from 'viem'
import { mainnet, sepolia } from 'viem/chains'
require("dotenv").config()
import {
    abi as Counter_ABI,
    bytecode as Counter_BYTECODE,
  } from '../../../artifacts/contracts/test/Counter.sol/Counter.json'
// import {
//     abi as Factory_ABI,
//     bytecode as Factory_BYTECODE,
//   } from '../../../artifacts/contracts/factory/IndexFactory.sol/IndexFactory.json'
import {
    abi as FactoryProcessor_ABI,
    bytecode as FactoryProcessor_BYTECODE,
  } from '../../../artifacts/contracts/factory/IndexFactoryProcessor.sol/IndexFactoryProcessor.json'
import {
abi as OrderProcessor_ABI,
bytecode as OrderProcessor_BYTECODE,
} from '../../../artifacts/contracts/dinary/orders/OrderProcessor.sol/OrderProcessor.json'
import { IndexFactoryAddresses, IndexFactoryProcessorAddresses, OrderProcessorAddresses, UsdcAddresses } from '../../../contractAddresses'
import { privateKeyToAccount } from 'viem/accounts'
// import { Event } from '../../../typechain-types/contracts/factory/TestIndexFactory';
import { Multicall } from '../../../typechain-types/@openzeppelin/contracts/utils/Multicall';
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
    
    console.log(logs);
    console.log(logs[0]?.args?.id)
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

async function multical(logs: any) {
  try {
  const id = logs[0]?.args?.id;
  console.log("checking id:", id)
  const isFilled = await client.readContract({
    address: IndexFactoryProcessorAddresses[`sepolia`] as `0x${string}`,
    abi: FactoryProcessor_ABI,
    args: [id],
    functionName: 'checkMultical',
  })
  
  console.log("status is:", isFilled)

  if(isFilled){
  console.log("Completing...")
  const { request } = await client.simulateContract({
      account,
      address: IndexFactoryProcessorAddresses[`sepolia`] as `0x${string}`,
      abi: FactoryProcessor_ABI,
      functionName: 'multical',
      args: [id]
    }) // Public Action
  const hash = await client.writeContract(request) // Wallet Action
  console.log("Completed !")
  }
 
  } catch (error) {
    console.log("Error:", error) 
  }
}

const unwatch = client.watchContractEvent({
    address: OrderProcessorAddresses[`sepolia`] as `0x${string}`,
    abi: OrderProcessor_ABI,
    eventName: 'OrderFulfilled',
    onLogs: logs => multical(logs)
  })