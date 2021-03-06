import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { verify } from "../helper-functions";
import {
  developmentChains,
  governorConfig,
  VERIFICATION_BLOCK_CONFIRMATIONS,
} from "../helper-hardhat.config";
import { network } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, log } = deployments;

  const { deployer } = await getNamedAccounts();
  const governanceToken = await deployments.get("GovernanceToken");
  const timeLock = await deployments.get("TimeLock");

  const { voting_delay, voting_period, quorum_fraction, proposal_threshold} = governorConfig

  const args = [governanceToken.address, timeLock.address, voting_delay, voting_period, quorum_fraction, proposal_threshold];
  const governor = await deploy("TheGovernor", {
    from: deployer,
    args: args,
    log: true,
    waitConfirmations: developmentChains.includes(network.name)
      ? 1
      : VERIFICATION_BLOCK_CONFIRMATIONS,
  });

  if (
    !developmentChains.includes(network.name) &&
    process.env.ETHERSCAN_API_KEY
  ) {
    log("Verifying...");
    await verify(governor.address, args, "contracts/onchain_governance/TheGoverner.sol:TheGovernor");
  }
};

export default func; // export default func; //can use whatever name in here. Hardhat deploy will import the export as "func"
func.tags = ["TheGovernor", "dao"];
