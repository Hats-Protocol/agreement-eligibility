import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Contract } from "zksync-ethers";
import * as hre from "hardhat";

const AgreementEligibilityFactory = require("../artifacts-zk/src/AgreementEligibilityFactory.sol/AgreementEligibilityFactory.json");

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const contractName = "AgreementEligibility";
const HATS_ID = 1;
const HATS = "0x32Ccb7600c10B4F7e678C7cbde199d98453D0e7e";
const SALT_NONCE = 1;
const FACTORY_ADDRESS = "0x18eE7bC80dD334D782C84E106216EB30f86D1CA9";

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set PRIVATE_KEY in your .env file";
  }

  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);
  const agreementEligibility = new Contract(
    FACTORY_ADDRESS,
    AgreementEligibilityFactory.abi,
    deployer.zkWallet
  );

  const tx = await agreementEligibility.deployModule(
    HATS_ID,
    HATS,
    "0x",
    SALT_NONCE
  );
  const tr = await tx.wait();
  console.log("Agreement eligibility module deployed at " + tr.contractAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
