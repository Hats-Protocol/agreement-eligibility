// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule, IHatsEligibility } from "hats-module/HatsEligibilityModule.sol";
import { MultiClaimsHatter } from "multi-claims-hatter/MultiClaimsHatter.sol";

/*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
//////////////////////////////////////////////////////////////*/

/// @dev Thrown when the caller does not wear the `ownerHat`
error AgreementEligibility_NotOwner();
/// @dev Thrown when the caller does not wear the `arbitratorHat`
error AgreementEligibility_NotArbitrator();
/// @dev Thrown when the hat is not mutable
error AgreementEligibility_HatNotMutable();

/**
 * @title AgreementEligibility
 * @author Haberdasher Labs
 * @notice A Hats Protocol module enabling individuals to permissionlessly claim a hat by signing an agreement
 */
contract AgreementEligibility is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @dev Emitted when a user "signs" the `agreement` and claims the hat
  event AgreementEligibility_HatClaimedWithAgreement(address claimer, uint256 hatId, string agreement);
  /// @dev Emitted when a user "signs" the `agreement` without claiming the hat
  event AgreementEligibility_AgreementSigned(address signer, string agreement);
  /// @dev Emitted when a new `agreement` is set
  event AgreementEligibility_AgreementSet(string agreement, uint256 grace);
  /// @dev Emitted when the `ownerHat` is set
  event AgreementEligibility_OwnerHatSet(uint256 newOwnerHat);
  /// @dev Emitted when the `arbitratorHat` is set
  event AgreementEligibility_ArbitratorHatSet(uint256 newArbitratorHat);
  /// @dev Emitted when a wearer's hat is revoked and placed in bad standing
  event AgreementEligibility_Revoked(address wearer);
  event AgreementEligibility_Revoked(address[] wearers);
  /// @dev Emitted when a wearer is forgiven and their standing restored
  event AgreementEligibility_Forgiven(address wearer);
  event AgreementEligibility_Forgiven(address[] wearers);

  /*//////////////////////////////////////////////////////////////
                              CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their locations.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * ------------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                               |
   * ------------------------------------------------------------------------|
   * Offset  | Constant            | Type      | Length | Source             |
   * ------------------------------------------------------------------------|
   * 0       | IMPLEMENTATION      | address   | 20     | HatsModule         |
   * 20      | HATS                | address   | 20     | HatsModule         |
   * 40      | hatId               | uint256   | 32     | HatsModule         |
   * ------------------------------------------------------------------------+
   */

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The hat ID for the owner hat
  uint256 public ownerHat;

  /// @notice The hat ID for the arbitrator hat
  uint256 public arbitratorHat;

  /// @dev The current agreement, typically as a CID of the agreement plaintext
  string public currentAgreement;

  /// @notice The id of the current agreement
  /// @dev The first agreement is id 1 (see {setUp}) so that id 0 can be used in {claimerAgreements} to indicate that an
  /// address has not signed any agreements
  uint256 public currentAgreementId;

  /// @notice The timestamp at which the current grace period ends. Existing wearers of `hatId` have until this time to
  /// sign the current agreement.
  uint256 public graceEndsAt;

  /// @notice The most recent agreement that each wearer has signed
  /// @dev agreementId=0 indicates that the wearer has not signed any agreements
  mapping(address claimer => uint256 agreementId) public claimerAgreements;

  /// @dev The inverse of the standing of each wearer; inversed so that wearers are in good standing by default
  mapping(address wearer => bool badStandings) internal _badStandings;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc HatsModule
  function _setUp(bytes calldata _initData) internal override {
    // decode init data
    (uint256 _ownerHat, uint256 _arbitratorHat, string memory agreement) =
      abi.decode(_initData, (uint256, uint256, string));

    // set the owner and arbitrator hats
    _setOwnerHat(_ownerHat);
    _setArbitratorHat(_arbitratorHat);

    // set the initial agreement
    currentAgreement = agreement;
    ++currentAgreementId;
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sign the current agreement and claim the hat
   * @param _claimsHatter a Multi Claims Hatter instance with which to perform claiming
   * @dev Mints the hat to the caller if:
   *     - the hat is "claimable-for" with the provided claims hatter instance, and
   *     - caller does not already wear the hat, and
   *     - caller is not in bad standing for the hat.
   */
  function signAgreementAndClaimHat(address _claimsHatter) public {
    uint256 agreementId = currentAgreementId; // save SLOADs

    // we need to set the claimer's agreement before minting so that they are eligible for the hat on minting
    claimerAgreements[msg.sender] = agreementId;

    /**
     * @dev this call will revert if...
     *       - the hat is not "claimable-for", or
     *       - caller is currently wearing the hat, or
     *       - caller is in bad standing for the hat
     */
    MultiClaimsHatter(_claimsHatter).claimHatFor(hatId(), msg.sender);

    emit AgreementEligibility_HatClaimedWithAgreement(msg.sender, hatId(), currentAgreement);
  }

  /**
   * @notice Sign the current agreement without claiming the hat.
   */
  function signAgreement() public {
    uint256 agreementId = currentAgreementId; // save SLOADs

    claimerAgreements[msg.sender] = agreementId;

    emit AgreementEligibility_AgreementSigned(msg.sender, currentAgreement);
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IHatsEligibility
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    standing = !_badStandings[_wearer];

    // bad standing means ineligible
    if (!standing) return (false, false);

    uint256 claimerAgreementId = claimerAgreements[_wearer]; // save SLOADs
    uint256 agreementId = currentAgreementId; // save SLOAD

    unchecked {
      // _wearer is eligible if they have signed the current agreement, or...
      if (claimerAgreementId == agreementId) {
        eligible = true;
        // if we are in a grace period and they have signed the previous agreement
        /// @dev agreementId is always > 0 after initialization, so this subtraction is safe
      } else if (block.timestamp < graceEndsAt && claimerAgreementId == agreementId - 1) {
        eligible = true;
      }
    }
  }

  /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Set a new agreement, with a grace period
   * @dev Only callable by a wearer of the `ownerHat`
   * @param _agreement The new agreement, as a hash of the agreement plaintext (likely a CID)
   * @param _grace The new grace period
   */
  function setAgreement(string calldata _agreement, uint256 _grace) public onlyOwner {
    uint256 _graceEndsAt = block.timestamp + _grace;

    graceEndsAt = _graceEndsAt;
    currentAgreement = _agreement;
    ++currentAgreementId;

    emit AgreementEligibility_AgreementSet(_agreement, _graceEndsAt);
  }

  /**
   * @notice Revoke the `_wearer`'s hat and place them in bad standing
   * @dev Only callable by a wearer of the `arbitratorHat`
   * @param _wearer The address of the wearer from whom to revoke the hat
   */
  function revoke(address _wearer) public onlyArbitrator {
    _revoke(_wearer, hatId());
    emit AgreementEligibility_Revoked(_wearer);
  }

  /**
   * @notice Revoke multiple wearers' hats
   * @dev Only callable by a wearer of the `arbitratorHat`
   * @param _wearers The addresses of the wearers from whom to revoke the hats
   */
  function revoke(address[] calldata _wearers) public onlyArbitrator {
    uint256 hatId = hatId();
    for (uint256 i; i < _wearers.length;) {
      _revoke(_wearers[i], hatId);

      unchecked {
        ++i;
      }
    }

    emit AgreementEligibility_Revoked(_wearers);
  }

  /**
   * @notice Forgive the `_wearer`'s bad standing, allowing them to claim the hat again
   * @dev Only callable by a wearer of the `arbitratorHat`
   * @param _wearer The address of the wearer to forgive
   */
  function forgive(address _wearer) public onlyArbitrator {
    _forgive(_wearer, hatId());
    emit AgreementEligibility_Forgiven(_wearer);
  }

  /**
   * @notice Forgive multiple `_wearers`' bad standings, allowing them to claim the hat again
   * @dev Only callable by a wearer of the `arbitratorHat`
   * @param _wearers The addresses of the wearers to forgive
   */
  function forgive(address[] calldata _wearers) public onlyArbitrator {
    uint256 hatId = hatId();
    for (uint256 i; i < _wearers.length;) {
      _forgive(_wearers[i], hatId);

      unchecked {
        ++i;
      }
    }

    emit AgreementEligibility_Forgiven(_wearers);
  }

  /**
   * @notice Set a new owner hat
   * @dev Only callable by a wearer of the current ownerHat, and only if the target hat is mutable
   * @param _newOwnerHat The new owner hat
   */
  function setOwnerHat(uint256 _newOwnerHat) public onlyOwner hatIsMutable {
    _setOwnerHat(_newOwnerHat);
  }

  /**
   * @notice Set a new arbitrator hat
   * @dev Only callable by a wearer of the current ownerHat, and only if the target hat is mutable
   * @param _newArbitratorHat The new arbitrator hat
   */
  function setArbitratorHat(uint256 _newArbitratorHat) public onlyOwner hatIsMutable {
    _setArbitratorHat(_newArbitratorHat);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Returns whether `_wearer` is in good standing
   * @param _wearer The address to check
   */
  function wearerStanding(address _wearer) public view returns (bool) {
    return !_badStandings[_wearer];
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /// @dev Set a new owner hat
  function _setOwnerHat(uint256 _newOwnerHat) internal {
    ownerHat = _newOwnerHat;

    emit AgreementEligibility_OwnerHatSet(_newOwnerHat);
  }

  function _setArbitratorHat(uint256 _newArbitratorHat) internal {
    arbitratorHat = _newArbitratorHat;

    emit AgreementEligibility_ArbitratorHatSet(_newArbitratorHat);
  }

  /// @dev Revoke a wearer's hat and set their standing to false in Hats.sol
  /// Unsafe. Does not check that the caller is wearing the arbitratorHat.
  function _revoke(address _wearer, uint256 _hatId) internal {
    _badStandings[_wearer] = true;

    // revoke _wearer's hat and set their standing to false in Hats.sol. We use the pull pattern (checkHatWearerStatus)
    // rather than the push pattern (setHatWearerStatus) for compatibility with module chains.
    HATS().checkHatWearerStatus(_hatId, _wearer);

    /**
     * @dev Hats.sol will emit the following events:
     *   1. ERC1155.TransferSingle (burn)
     *   2. Hats.WearerStandingChanged
     */
  }

  /// @dev Forgive a wearer and set their standing to true in Hats.sol
  /// Unsafe. Does not check that the caller is wearing the arbitratorHat.
  function _forgive(address _wearer, uint256 _hatId) internal {
    _badStandings[_wearer] = false;

    // return the wearer to good standing in Hats.sol. We use the pull pattern (checkHatWearerStatus) rather than the
    // push pattern (setHatWearerStatus) for compatibility with module chains.
    HATS().checkHatWearerStatus(_hatId, _wearer);

    /// @dev Hats.sol will emit a Hats.WearerStandingChanged event
  }

  /*//////////////////////////////////////////////////////////////
                            MODIFERS
  //////////////////////////////////////////////////////////////*/

  /// @notice Reverts if the caller is not wearing the ownerHat.
  modifier onlyOwner() {
    if (!HATS().isWearerOfHat(msg.sender, ownerHat)) revert AgreementEligibility_NotOwner();
    _;
  }

  /// @notice Reverts if the caller is not wearing the arbitratorHat.
  modifier onlyArbitrator() {
    if (!HATS().isWearerOfHat(msg.sender, arbitratorHat)) revert AgreementEligibility_NotArbitrator();
    _;
  }

  /// @notice Reverts if the hatid is not mutable
  modifier hatIsMutable() {
    (,,,,,,, bool isMutable,) = HATS().viewHat(hatId());
    if (!isMutable) revert AgreementEligibility_HatNotMutable();
    _;
  }
}
