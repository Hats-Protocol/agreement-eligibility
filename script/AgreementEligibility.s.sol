// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Script, console2 } from "forge-std/Script.sol";
import { AgreementEligibility } from "../src/AgreementEligibility.sol";
import { HatsModuleFactory } from "../lib/hats-module/src/HatsModuleFactory.sol";

contract Deploy is Script {
  address public implementation;
  bytes32 public SALT = bytes32(abi.encode(0x4a75)); // "hats"

  // default values
  bool private verbose = true;
  string private version = "0.4.0"; // increment with each deployment

  /// @notice Override default values, if desired
  function prepare(bool _verbose, string memory _version) public {
    verbose = _verbose;
    version = _version;
  }

  function run() public {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.rememberKey(privKey);
    vm.startBroadcast(deployer);

    implementation = address(new AgreementEligibility{ salt: SALT }(version));

    vm.stopBroadcast();

    if (verbose) {
      console2.log("Implementation:", implementation);
    }
  }

  // forge script script/AgreementEligibility.s.sol:Deploy -f ethereum --broadcast --verify

  /* 
  forge verify-contract --chain-id 11155111 --num-of-optimizations 1000000 --watch \
  --constructor-args $(cast abi-encode "constructor(string)" "0.4.0" ) \
  --compiler-version v0.8.19 0x4F10B9e99ce11f081652646f4b192ed1b812D5Bb \
  src/AgreementEligibility.sol:AgreementEligibility --etherscan-api-key $ETHERSCAN_KEY 
  */
}

contract DeployInstance is Script {
  HatsModuleFactory public factory = HatsModuleFactory(0x0a3f85fa597B6a967271286aA0724811acDF5CD9);
  AgreementEligibility public instance;

  // default values
  bool internal _verbose = true;
  address internal _implementation = 0x4F10B9e99ce11f081652646f4b192ed1b812D5Bb; // 0.4.0

  uint256 internal _saltNonce = 1;
  uint256 internal _hatId = 0x000000380001000a000000000000000000000000000000000000000000000000; // 56.1.10
  uint256 internal _ownerHat = 0x0000003800010000000000000000000000000000000000000000000000000000; // 56.1.0
  uint256 internal _arbitratorHat = 0x0000003800010000000000000000000000000000000000000000000000000000; // 56.1.0
  string internal _agreement = "ipfs://QmPK856cK97JH74S3VCo8v2UNPdE6TAzHcizzG3mpCJdpp";

  /// @dev Override default values, if desired
  function prepare(
    bool verbose,
    address implementation,
    uint256 hatId,
    uint256 ownerHat,
    uint256 arbitratorHat,
    string memory agreement,
    uint256 saltNonce
  ) public {
    _verbose = verbose;
    _implementation = implementation;
    _hatId = hatId;
    _saltNonce = saltNonce;
    _ownerHat = ownerHat;
    _arbitratorHat = arbitratorHat;
    _agreement = agreement;
  }

  /// @dev Set up the deployer via their private key from the environment
  function deployer() public returns (address) {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    return vm.rememberKey(privKey);
  }

  function _log(string memory prefix) internal view {
    if (_verbose) {
      console2.log(string.concat(prefix, "Instance:"), address(instance));
    }
  }

  function run() public virtual returns (AgreementEligibility) {
    vm.startBroadcast(deployer());

    instance = AgreementEligibility(
      factory.createHatsModule(
        _implementation,
        _hatId,
        abi.encodePacked(), // other immutable args
        abi.encode(_ownerHat, _arbitratorHat, _agreement), // init data
        _saltNonce
      )
    );

    vm.stopBroadcast();

    _log("");
    console2.log("version:", instance.version());
    console2.log("agreement:", instance.currentAgreement());
    console2.log("hatId:", instance.hatId());
    console2.log("ownerHat:", instance.ownerHat());
    console2.log("arbitratorHat:", instance.arbitratorHat());

    return instance;
  }

  // forge script script/AgreementEligibility.s.sol:DeployInstance -f ethereum --broadcast
}
