// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";

import {
  AgreementEligibility,
  AgreementEligibility_NotOwner,
  AgreementEligibility_NotArbitrator,
  AgreementEligibility_HatNotMutable
} from "../src/AgreementEligibility.sol";
import { Deploy, DeployInstance } from "../script/AgreementEligibility.s.sol";
import {
  IHats,
  HatsModuleFactory,
  deployModuleFactory,
  deployModuleInstance
} from "lib/hats-module/src/utils/DeployFunctions.sol";
import { MultiClaimsHatter } from "multi-claims-hatter/MultiClaimsHatter.sol";

contract AgreementEligibilityTest is Deploy, Test {
  // variables inhereted from Deploy script
  // address public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 19_467_227; // deployment block for HatsModuleFactory v0.7.0
  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth

  string public FACTORY_VERSION = "factory test version";
  string public MODULE_VERSION = "module test version";

  event AgreementEligibility_HatClaimedWithAgreement(address claimer, uint256 hatId, string agreement);
  event AgreementEligibility_AgreementSigned(address signer, string agreement);
  event AgreementEligibility_AgreementSet(string agreement, uint256 grace);
  event AgreementEligibility_OwnerHatSet(uint256 newOwnerHat);
  event AgreementEligibility_ArbitratorHatSet(uint256 newArbitratorHat);
  event AgreementEligibility_Revoked(address wearer);
  event AgreementEligibility_Revoked(address[] wearers);
  event AgreementEligibility_Forgiven(address wearer);
  event AgreementEligibility_Forgiven(address[] wearers);

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    Deploy.prepare(false, MODULE_VERSION); // set first param to true to log deployment addresses
    Deploy.run();
  }
}

contract WithInstanceTest is AgreementEligibilityTest {
  enum ClaimType {
    NotClaimable,
    Claimable,
    ClaimableFor
  }

  HatsModuleFactory public factory = HatsModuleFactory(0x0a3f85fa597B6a967271286aA0724811acDF5CD9);
  uint256 public constant SALT_NONCE = 1;
  AgreementEligibility public instance;
  MultiClaimsHatter public claimsHatter;

  bytes public otherImmutableArgs;
  bytes public initData;

  uint256 public tophat;
  uint256 public claimableHat;
  // owner hat will be the tophat
  uint256 public arbitratorHat;
  uint256 public registrarHat;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public arbitrator = makeAddr("arbitrator");
  address public claimer1 = makeAddr("claimer1");
  address public claimer2 = makeAddr("claimer2");
  address public claimer3 = makeAddr("claimer3");
  address public claimer4 = makeAddr("claimer4");
  address public claimer5 = makeAddr("claimer5");
  address public nonWearer = makeAddr("nonWearer");

  string public agreement;
  uint256 public gracePeriod;
  uint256 public currentAgreementId;

  function deployAgreementEligibilityInstance(
    uint256 _claimableHat,
    uint256 _ownerHat,
    uint256 _arbitratorHat,
    string memory _agreement
  ) public returns (AgreementEligibility) {
    // create DeployInstance script and use it here
    DeployInstance instanceDeployer = new DeployInstance();
    instanceDeployer.prepare(
      false, address(implementation), _claimableHat, _ownerHat, _arbitratorHat, _agreement, SALT_NONCE
    );
    return instanceDeployer.run();
  }

  function deployMultiClaimsHatterInstance(
    uint256 _hatId,
    uint256[] memory _claimableHats,
    ClaimType[] memory _claimTypes
  ) public returns (MultiClaimsHatter) {
    // encoded the initData as unpacked bytes
    initData = abi.encode(_claimableHats, _claimTypes);
    // deploy the instance
    return MultiClaimsHatter(
      deployModuleInstance(
        factory, address(0xB985eA1be961f7c4A4C45504444C02c88c4fdEF9), _hatId, "", initData, SALT_NONCE
      )
    );
  }

  function _claimers() internal view returns (address[] memory) {
    address[] memory claimers = new address[](5);
    claimers[0] = claimer1;
    claimers[1] = claimer2;
    claimers[2] = claimer3;
    claimers[3] = claimer4;
    claimers[4] = claimer5;
    return claimers;
  }

  function setUp() public virtual override {
    super.setUp();
    gracePeriod = 7 days;

    // deploy the hats module factory
    factory = deployModuleFactory(HATS, SALT, FACTORY_VERSION);

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    registrarHat = HATS.createHat(tophat, "registrarHat", 1, eligibility, toggle, true, "dao.eth/registrarHat");
    claimableHat = HATS.createHat(registrarHat, "claimableHat", 50, eligibility, toggle, true, "dao.eth/claimableHat");
    arbitratorHat = HATS.createHat(tophat, "arbitratorHat", 1, eligibility, toggle, true, "dao.eth/arbitratorHat");
    HATS.mintHat(arbitratorHat, arbitrator);
    vm.stopPrank();

    // deploy an instance of multi calims hatter
    uint256[] memory claimableHats = new uint256[](1);
    ClaimType[] memory claimTypes = new ClaimType[](1);
    claimableHats[0] = claimableHat;
    claimTypes[0] = ClaimType.ClaimableFor;
    claimsHatter = deployMultiClaimsHatterInstance(registrarHat, claimableHats, claimTypes);
    vm.prank(dao);
    HATS.mintHat(registrarHat, address(claimsHatter));

    // set up initial agreement
    agreement = "this is the first agreement";

    // deploy the instance
    instance = deployAgreementEligibilityInstance(claimableHat, tophat, arbitratorHat, agreement);

    // set instance as claimableHat's eligibility module
    vm.prank(dao);
    HATS.changeHatEligibility(claimableHat, address(instance));
  }
}

contract Deployment is WithInstanceTest {
  function test_version() public view {
    assertEq(instance.version(), MODULE_VERSION);
  }

  function test_implementation() public view {
    assertEq(address(instance.IMPLEMENTATION()), address(implementation));
  }

  function test_hats() public view {
    assertEq(address(instance.HATS()), address(HATS));
  }

  function test_claimableHat() public view {
    assertEq(instance.hatId(), claimableHat);
  }

  function test_ownerHat() public view {
    assertEq(instance.ownerHat(), tophat);
  }

  function test_arbitratorHat() public view {
    assertEq(instance.arbitratorHat(), arbitratorHat);
  }

  function test_agreement() public view {
    assertEq(instance.currentAgreement(), agreement);
  }

  function test_agreementId() public view {
    assertEq(instance.currentAgreementId(), 1);
  }
}

contract SetAgreement is WithInstanceTest {
  function setUp() public virtual override {
    super.setUp();
    agreement = "this is the new agreement";
  }

  function test_happy() public {
    gracePeriod = 20 days;

    vm.expectEmit();
    emit AgreementEligibility_AgreementSet(agreement, block.timestamp + gracePeriod);

    vm.prank(dao);
    instance.setAgreement(agreement, gracePeriod);

    assertEq(instance.currentAgreement(), agreement);
    assertEq(instance.currentAgreementId(), 2);
    assertEq(instance.graceEndsAt(), block.timestamp + gracePeriod);
  }

  function test_revert_notOwner() public {
    gracePeriod = 20 days;

    vm.expectRevert(AgreementEligibility_NotOwner.selector);

    vm.prank(nonWearer);
    instance.setAgreement(agreement, gracePeriod);
  }
}

contract Claim is WithInstanceTest {
  function test_happy_1claimer() public {
    assertTrue(claimsHatter.isClaimableFor(claimableHat), "hat is not claimable for");

    vm.expectEmit();
    emit AgreementEligibility_HatClaimedWithAgreement(claimer1, claimableHat, agreement);

    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_happy_2claimers() public {
    // first claim
    vm.expectEmit();
    emit AgreementEligibility_HatClaimedWithAgreement(claimer1, claimableHat, agreement);

    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // second claim
    vm.expectEmit();
    emit AgreementEligibility_HatClaimedWithAgreement(claimer2, claimableHat, agreement);

    vm.prank(claimer2);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer2), 1);
    assertTrue(HATS.isWearerOfHat(claimer2, claimableHat));
  }

  function test_revert_alreadyWearingHat() public {
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // now try again, expecting a revert
    vm.expectRevert();
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));
  }

  function test_revert_notEligible() public {
    // claim
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // get revoked
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    // try to claim again, expected revert because in bad standing
    vm.prank(claimer1);
    vm.expectRevert();
    instance.signAgreementAndClaimHat(address(claimsHatter));
  }
}

contract SignAgreement is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // new agreement is set
    string memory newAgreement = "this is the new agreement";
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.expectEmit();
    emit AgreementEligibility_AgreementSigned(claimer1, newAgreement);

    vm.prank(claimer1);
    instance.signAgreement();

    assertEq(instance.claimerAgreements(claimer1), 2);
  }

  function test_afterGracePeriod() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    assertEq(instance.claimerAgreements(claimer1), 1);
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));

    // new agreement is set
    string memory newAgreement = "this is the new agreement";
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // warp past the grace period
    vm.warp(instance.graceEndsAt());

    // not wearing the hat any more
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));

    // sign the new agreement
    vm.expectEmit();
    emit AgreementEligibility_AgreementSigned(claimer1, newAgreement);

    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // now wearing the hat again
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }
}

contract Revoke is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // revoke
    vm.expectEmit();
    emit AgreementEligibility_Revoked(claimer1);

    vm.prank(arbitrator);
    instance.revoke(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_revert_notArbitrator() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // attempt to revoke from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementEligibility_NotArbitrator.selector);
    instance.revoke(claimer1);

    assertTrue(instance.wearerStanding(claimer1));
    assertTrue(HATS.isWearerOfHat(claimer1, claimableHat));
  }
}

contract RevokeMultiple is WithInstanceTest {
  address[] public claimers;

  function setUp() public virtual override {
    super.setUp();
    claimers = _claimers();
  }

  function test_happy(uint256 _numClaimers) public {
    _numClaimers = bound(_numClaimers, 1, 5);

    // claim hats
    for (uint256 i; i < _numClaimers; ++i) {
      vm.prank(claimers[i]);
      instance.signAgreementAndClaimHat(address(claimsHatter));
    }

    // revoke all the claimers
    vm.expectEmit();
    emit AgreementEligibility_Revoked(claimers);

    vm.prank(arbitrator);
    instance.revoke(claimers);

    // check that all claimers are revoked
    for (uint256 i; i < _numClaimers; ++i) {
      assertFalse(instance.wearerStanding(claimers[i]));
      assertFalse(HATS.isWearerOfHat(claimers[i], claimableHat));
    }
  }

  function test_revert_notArbitrator(uint256 _numClaimers) public {
    _numClaimers = bound(_numClaimers, 1, 5);

    // claim the hats
    for (uint256 i; i < _numClaimers; ++i) {
      vm.prank(claimers[i]);
      instance.signAgreementAndClaimHat(address(claimsHatter));
    }

    // attempt to revoke from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementEligibility_NotArbitrator.selector);
    instance.revoke(claimers);

    // check that all claimers are still wearing the hat
    for (uint256 i; i < _numClaimers; ++i) {
      assertTrue(instance.wearerStanding(claimers[i]));
      assertTrue(HATS.isWearerOfHat(claimers[i], claimableHat));
    }
  }
}

contract Forgive is WithInstanceTest {
  function test_happy() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));

    // forgive
    vm.expectEmit();
    emit AgreementEligibility_Forgiven(claimer1);

    vm.prank(arbitrator);
    instance.forgive(claimer1);

    assertTrue(instance.wearerStanding(claimer1));
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  function test_revert_notArbitrator() public {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    // attempt to forgive from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementEligibility_NotArbitrator.selector);
    instance.forgive(claimer1);

    assertFalse(instance.wearerStanding(claimer1));
  }
}

contract ForgiveMultiple is WithInstanceTest {
  address[] public claimers;

  function setUp() public virtual override {
    super.setUp();
    claimers = _claimers();
  }

  function test_happy(uint256 _numClaimers) public {
    _numClaimers = bound(_numClaimers, 1, 5);

    // claim hats
    for (uint256 i; i < _numClaimers; ++i) {
      vm.prank(claimers[i]);
      instance.signAgreementAndClaimHat(address(claimsHatter));
    }

    // revoke all the claimers
    vm.prank(arbitrator);
    instance.revoke(claimers);

    // forgive all the claimers
    vm.expectEmit();
    emit AgreementEligibility_Forgiven(claimers);

    vm.prank(arbitrator);
    instance.forgive(claimers);

    // check that all claimers are forgiven but not wearing the hat
    for (uint256 i; i < _numClaimers; ++i) {
      assertTrue(instance.wearerStanding(claimers[i]));
      assertFalse(HATS.isWearerOfHat(claimers[i], claimableHat));
    }
  }

  function test_revert_notArbitrator(uint256 _numClaimers) public {
    _numClaimers = bound(_numClaimers, 1, 5);

    // claim hats
    for (uint256 i; i < _numClaimers; ++i) {
      vm.prank(claimers[i]);
      instance.signAgreementAndClaimHat(address(claimsHatter));
    }

    // revoke all the claimers
    vm.prank(arbitrator);
    instance.revoke(claimers);

    // attempt to forgive from non-arbitrator, expecting revert
    vm.prank(nonWearer);
    vm.expectRevert(AgreementEligibility_NotArbitrator.selector);
    instance.forgive(claimers);

    // check that all claimers are still revoked
    for (uint256 i; i < _numClaimers; ++i) {
      assertFalse(instance.wearerStanding(claimers[i]));
      assertFalse(HATS.isWearerOfHat(claimers[i], claimableHat));
    }
  }
}

contract WearerStatus is WithInstanceTest {
  bool public eligible;
  bool public standing;
  string newAgreement = "this is the new agreement";

  function test_claimed() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, true);
    assertEq(standing, true);
  }

  function test_signedNew() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, true);
    assertEq(standing, true);
  }

  function test_signedOld_inGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // don't sign the new agreement
    assertEq(instance.claimerAgreements(claimer1), 1);

    // warp to within grace period
    vm.warp(instance.graceEndsAt() - 1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
  }

  function test_signedOld_afterGracePeriod() public notEligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // don't sign the new agreement
    assertEq(instance.claimerAgreements(claimer1), 1);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, false);
    assertEq(standing, true);
  }

  function test_signedPrevious_inGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // 3rd agreement is set
    vm.prank(dao);
    instance.setAgreement("this is the 3rd agreement", gracePeriod);

    // don't sign the 3rd agreement
    assertEq(instance.claimerAgreements(claimer1), 2);

    // warp to in grace period
    vm.warp(instance.graceEndsAt() - 1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, true);
    assertEq(standing, true);
  }

  function test_signedNew_afterGracePeriod() public Eligible goodStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // new agreement is set
    vm.prank(dao);
    instance.setAgreement(newAgreement, gracePeriod);

    // sign the new agreement
    vm.prank(claimer1);
    instance.signAgreement();
    assertEq(instance.claimerAgreements(claimer1), 2);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, true);
    assertEq(standing, true);
  }

  function test_revoked() public notEligible badStanding {
    // claim the hat
    vm.prank(claimer1);
    instance.signAgreementAndClaimHat(address(claimsHatter));

    // revoke
    vm.prank(arbitrator);
    instance.revoke(claimer1);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, false);
    assertEq(standing, false);
  }

  function test_notClaimed_afterGracePeriod() public notEligible goodStanding {
    // not claimed
    assertEq(instance.claimerAgreements(claimer1), 0);

    // warp to after grace period
    vm.warp(instance.graceEndsAt());

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, false);
    assertEq(standing, true);
  }

  function test_notClaimed_inGracePeriod() public notEligible goodStanding {
    // not claimed
    assertEq(instance.claimerAgreements(claimer1), 0);

    (eligible, standing) = instance.getWearerStatus(claimer1, 0);
    assertEq(eligible, false);
    assertEq(standing, true);
  }

  modifier notEligible() {
    _;
    assertFalse(eligible);
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  modifier Eligible() {
    _;
    assertTrue(eligible);
  }

  modifier badStanding() {
    _;
    assertFalse(standing);
    assertFalse(HATS.isWearerOfHat(claimer1, claimableHat));
  }

  modifier goodStanding() {
    _;
    assertTrue(standing);
  }
}

contract SetOwnerHat is WithInstanceTest {
  function test_owner_mutable() public {
    uint256 newOwnerHat = 1;
    vm.expectEmit();
    emit AgreementEligibility_OwnerHatSet(newOwnerHat);

    vm.prank(dao);
    instance.setOwnerHat(newOwnerHat);
  }

  function test_revert_nonOwner_mutable() public {
    uint256 newOwnerHat = 1;
    vm.expectRevert(AgreementEligibility_NotOwner.selector);

    vm.prank(nonWearer);
    instance.setOwnerHat(newOwnerHat);
  }

  function test_revert_owner_immutable() public {
    uint256 newOwnerHat = 1;

    vm.prank(dao);
    HATS.makeHatImmutable(claimableHat);

    vm.expectRevert(AgreementEligibility_HatNotMutable.selector);

    vm.prank(dao);
    instance.setOwnerHat(newOwnerHat);
  }
}

contract SetArbitratorHat is WithInstanceTest {
  function test_arbitrator_mutable() public {
    uint256 newArbitratorHat = 1;
    vm.expectEmit();
    emit AgreementEligibility_ArbitratorHatSet(newArbitratorHat);

    vm.prank(dao);
    instance.setArbitratorHat(newArbitratorHat);
  }

  function test_revert_nonOwner_mutable() public {
    uint256 newArbitratorHat = 1;
    vm.expectRevert(AgreementEligibility_NotOwner.selector);

    vm.prank(nonWearer);
    instance.setArbitratorHat(newArbitratorHat);
  }

  function test_revert_arbitrator_immutable() public {
    uint256 newArbitratorHat = 1;

    vm.prank(dao);
    HATS.makeHatImmutable(claimableHat);

    vm.expectRevert(AgreementEligibility_HatNotMutable.selector);

    vm.prank(dao);
    instance.setArbitratorHat(newArbitratorHat);
  }
}
