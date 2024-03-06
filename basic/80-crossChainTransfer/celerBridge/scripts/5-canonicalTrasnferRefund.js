// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const {ethers} = require("hardhat");
const fetch = require("node-fetch");

const {
  readRedpacketDeployment,
} = require("../utils");

const request = (url, params = {}, method = "GET") => {
  let options = {
    method,
  };
  if ("GET" === method) {
    url += "?" + new URLSearchParams(params).toString();
  } else {
    options.body = JSON.stringify(params);
  }

  return fetch(url, options).then((response) => response.json());
};


async function getTransferStatus(transferID){
  const fetchPostRes = await request(
    "https://cbridge-prod2.celer.app/v2/getTransferStatus",
    {
      transfer_id:
      transferID,
    },
    "POST"
  );

  return fetchPostRes
}

async function refundCanonicalTransfer(transferStatus,deployer){
  const wdmsg = ethers.utils.base64.decode(transferStatus.wd_onchain);
  
  const signers = transferStatus.signers.map(item => {
    const decodeSigners = ethers.utils.base64.decode(item);
    const hexlifyObj = ethers.utils.hexlify(decodeSigners);
    return ethers.utils.getAddress(hexlifyObj);
  });

  const sigs = transferStatus.sorted_sigs.map(item => {
    return ethers.utils.base64.decode(item);
  });

  const powers = transferStatus.powers.map(item => {
    return ethers.utils.base64.decode(item);
  });

  // canonical bridge contract on Op mainnet
  const canonicalBridgeContract = "0xbCfeF6Bb4597e724D720735d32A9249E0640aA11"
  const bridge = await hre.ethers.getContractAt('OriginalTokenVault', canonicalBridgeContract, deployer);
  let receipt = await bridge.withdraw(wdmsg,sigs,signers,powers)
  console.log(receipt)
}


async function main() {
  const deployment = readRedpacketDeployment();
  const [deployer] = await ethers.getSigners();
  // get transfer status
  // refer to: https://cbridge-docs.celer.network/developer/api-reference/gateway-gettransferstatus
  console.log("Begin to check cross chain transfer result")
  let bridgeID = deployment.canonicalCelerBridgeTransferID
  let transferStatus = await getTransferStatus(bridgeID)
  switch(transferStatus.status){
    case 0:
      console.log("Placeholder status")
      break; 
    case 1:
      console.log("cBridge gateway monitoring on-chain transaction")
      break; 
    case 2:
      console.log("transfer failed, no need to refund")
      break;
    case 3:
      console.log("cBridge gateway waiting for Celer SGN confirmation")
      break;
    case 4:
      console.log("waiting for user's fund release on destination chain")
      break;
    case 5:
      console.log("Transfer completed")
      break;
    case 6:
      console.log("Transfer failed, should trigger refund flow, whether it is Pool-Based or Mint/Burn refund​")
      break;
    case 7:
      console.log("cBridge gateway is preparing information for user's transfer refund​")
      break;
    case 8:
      console.log("The user should submit on-chain refund transaction based on information provided by this api​")
      break;
    case 9:
      console.log("cBridge monitoring transfer refund status on source chain​")
      break;
    case 10:
      console.log("Transfer refund completed​")
      break;
    case 11:
      console.log("Transfer is put into a delayed execution queue​")
      break;
  }
  
  if(transferStatus.status == 8){
    console.log("Begin to refund======")
    await refundCanonicalTransfer(transferStatus,deployer);
    console.log("Refund successfully")
  }

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
