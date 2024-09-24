require("dotenv").config();

async function main() {
    // console.log(process.env.ANGINE_API_KEY)
    // return;
    const resp = await fetch(
        // "<engine_url>/contract/<chain>/<contract_address>/read?functionName=balanceOf&args=0x3EcDBF3B911d0e9052b64850693888b008e18373",
        // "https://localhost:3005/contract/11155111/0x007F64Ad841C4Bc26E290b2137eD8374466A1359/read?functionName=number",
        "https://localhost:3005/backend-wallet/11155111/0xAa616c842329bd5bdCEc6b0035290389C34F6682/get-balance",
        {
          headers: {
            // Authorization: "Bearer <access_token>",
            Authorization: `Bearer ${process.env.ANGINE_API_KEY as string}`,
            // Authorization: process.env.ANGINE_API_KEY as string,
          },
        },
      );
       
      const { result } = await resp.json();
      console.log("ERC-20 balance:", result);
}

main();