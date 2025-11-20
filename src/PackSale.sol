// SPDX-License-Identifier: MIT
// Copyright (C) 2023-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./BoolSet.sol";
import "./ClubMinter.sol";
import "./ISanctionsList.sol";
import "./PurchaseTracker.sol";
import "./ReferralTracker.sol";

using BoolSet for BoolSet.Type;

/**
 * @dev This contract implements the on-chain sale of share packs in clubs.
 * It has the configuration about which clubs are available in one of the
 * pack tiers, what the pricing curve is for the tier, and what other
 * configuration is required as well as the current pseudo-random seed.
 *
 * It takes payment (sent to a configured payee address) in an ERC20 token
 * such as USDC, and requests the in-game minting of shares from a ClubMinter.
 *
 * Each pack tier has its own sales contract, with the corresponding
 * configuration and list of clubs.
 */
contract PackSale is ERC2771Context, AccessControlEnumerable, Pausable
{

  /** @dev Addresses with this role can change the sale config.  */
  bytes32 public constant CONFIGURE_ROLE = keccak256 ("CONFIGURE_ROLE");

  /** @dev Addresses with this role can update the random seed.  */
  bytes32 public constant UPDATE_SEED_ROLE = keccak256 ("UPDATE_SEED_ROLE");

  /**
   * @dev The ClubMinter contract used to mint shares.  The PackSale contract
   * must be an authorised minter on it.
   */
  ClubMinter public immutable minter;

  /** @dev The purchase tracker used.  */
  PurchaseTracker public immutable purchaseTracker;

  /** @dev The referral tracker used.  */
  ReferralTracker public immutable refTracker;

  /** @dev The token used for payments.  */
  IERC20Metadata public immutable token;

  /**
   * @dev The pack tier this corresponds to.  The value is here just for
   * documentation and debugging purposes, and does not have any effect.
   *
   * This value is actually immutable (set only in the constructor and then
   * never changed), but as a string it can't be declared as such.
   */
  string public tier;

  /** @dev Receiver of sale proceeds.  */
  address public payee;

  /**
   * @dev When configuring the "bonding curve" for available shares in each
   * club and their pricing, we use a step function:  First X shares for Y,
   * then next Z shares for Q, and so on.  This struct represents one of
   * these steps.
   */
  struct PricingStep
  {

    /**
     * @dev The number of shares available at the given price.  This is for
     * the current step only, not cumulative.
     */
    uint num;

    /**
     * @dev Price of one share in this batch, in the base unit (smallest
     * decimal) of the payment token.
     */
    uint price;

  }

  /**
   * @dev The steps of the pricing function for club shares.  Each club
   * follows this function individually, based on how many shares have been
   * minted for it already from the ClubMinter.  This defines both the pricing
   * of packs and the availability of shares.
   */
  PricingStep[] public pricing;

  /**
   * @dev Total number of shares available for sale in each club.  This is
   * based on the pricing curve (sum of all "num" members of the steps),
   * but cached here for efficiency.  A particular club is considered available
   * until this number of shares have been minted by the ClubMinter.
   */
  uint public totalSharesAvailable;

  /** @dev Number of secondary clubs to include in a pack.  */
  uint public secondaryClubs;

  /** @dev Number of shares of the primary (user-selected) club.  */
  uint public numSharesPrimary;

  /** @dev Number of shares of the secondary (randomly chosen) clubs.  */
  uint public numSharesSecondary;

  /**
   * @dev Shares in the primary club to give to the referrer whenever
   * a referral buys a pack.  This is expressed as basis points.
   */
  uint public refBonusBps;

  /**
   * @dev How many seconds after the initial referral event a referral bonus
   * will be granted.
   */
  uint public refBonusSeconds;

  /** @dev Base value for the ref bonus.  */
  uint public constant refBonusBase = 10000;

  /**
   * @dev Number of SMC that the primary club is minted when a pack is
   * bought.  This is per unit value of the payment token paid, e.g. SMC
   * given for each $1 paid (not the base unit of the token!), based on the
   * total paid by a user for their pack.
   */
  uint public smcMintedPerUsd;

  /**
   * @dev The oracle used to sanction screen addresses before they are allowed
   * to purchase packs.  If this is zero, no checks are done.
   */
  ISanctionsList public sanctionsList;

  /** @dev Purchase threshold before KYC approval is required.  */
  uint public kycThreshold;

  /** @dev All club IDs that belong to this tier.  */
  uint[] public clubIds;

  /**
   * @dev All clubs that are currently configured.  The value of each entry
   * is the index of that club into "clubIds" plus one or zero if the club
   * does not belong to this tier.
   */
  mapping (uint => uint) public clubIndices;

  /**
   * @dev A list of clubs whose sale is paused.  This are clubs that
   * have been found as sold out, but where configured to be part of
   * this tier.  They are kept in this place so that there remains
   * a record of which clubs are/were originally part of the tier, and
   * so that they can be restored easily when more shares become
   * available for sale.
   */
  uint[] public pausedClubs;

  /**
   * @dev The current seed for pseudo-random numbers.  This is changed
   * from time to time (possible by the UPDATE_SEED_ROLE), but is known before
   * an actual mint, so the minter knows exactly what they get.
   */
  bytes32 seed;

  /** @dev Emitted when the payee is changed.  */
  event PayeeChanged (address payee);

  /** @dev Emitted when the base config is updated.  */
  event Configured (uint secondaryClubs,
                    uint numSharesPrimary, uint numSharesSecondary);

  /** @dev Emitted when the referral bonus is changed.  */
  event RefBonusUpdated (uint refBonusBps, uint refBonusSeconds);

  /** @dev Emitted when the SMC mint rate has been changed.  */
  event SmcMintRateUpdated (uint newSmcPerUsd);

  /** @dev Emitted when the pricing curve is updated.  */
  event PricingUpdated (PricingStep[] steps);

  /** @dev Emitted when the sanctions oracle is changed.  */
  event SanctionsListUpdated (ISanctionsList newList);

  /** @dev Emitted when the KYC threshold is changed.  */
  event KycThresholdUpdated (uint newThreshold);

  /** @dev Emitted when a club is added.  */
  event ClubAdded (uint indexed clubId);

  /** @dev Emitted when a club is removed.  */
  event ClubRemoved (uint indexed clubId);

  /** @dev Emitted when a club is paused.  */
  event ClubSalePaused (uint indexed clubId);

  /** @dev Emitted when a club is unpaused.  */
  event ClubSaleUnpaused (uint indexed clubId);

  /** @dev Emitted when the random seed is changed.  */
  event SeedUpdated (bytes32 seed);

  /** @dev Emitted when one or more packs are bought.  */
  event PacksBought (address indexed buyer, string receiver,
                     uint indexed primaryClubId, uint numPacks, uint cost);

  /** @dev Emitted when a referral bonus is given.  */
  event ReferralBonusGiven (string buyer, string referrer,
                            uint clubId, uint numShares,
                            uint numPacksBought, uint cost);

  /* ************************************************************************ */

  constructor (IERC20Metadata t, ClubMinter m,
               PurchaseTracker pt, ReferralTracker rt,
               string memory nm, address fwd)
    ERC2771Context(fwd)
  {
    _grantRole (DEFAULT_ADMIN_ROLE, msg.sender);

    token = t;
    minter = m;
    purchaseTracker = pt;
    refTracker = rt;
    tier = nm;

    /* We start with no KYC threshold, but it can be configured
       later on by the CONFIGURE_ROLE.  */
    kycThreshold = type (uint256).max;

    updateSeedInternal ();
  }

  /* Explicitly specify that we want to use the ERC2771 variants for
     _msgSender and _msgData.  */

  function _msgSender ()
      internal view override(Context, ERC2771Context) returns (address)
  {
    return ERC2771Context._msgSender ();
  }

  function _msgData ()
      internal view override(Context, ERC2771Context) returns (bytes calldata)
  {
    return ERC2771Context._msgData ();
  }

  function _contextSuffixLength ()
      internal view override(Context, ERC2771Context) returns (uint256)
  {
    return ERC2771Context._contextSuffixLength ();
  }

  function pause () public onlyRole (CONFIGURE_ROLE)
  {
    _pause ();
  }

  function unpause () public onlyRole (CONFIGURE_ROLE)
  {
    _unpause ();
  }

  /* ************************************************************************ */

  /**
   * @dev Sets the payee (which is the address receiving any funds from
   * purchased packs).  If it is set to the zero address, then no purchases
   * are possible.
   */
  function setPayee (address p) public onlyRole (CONFIGURE_ROLE)
  {
    payee = p;
    emit PayeeChanged (p);
  }

  /**
   * @dev Configures the base values.
   */
  function configure (uint sec, uint np, uint ns)
      public onlyRole (CONFIGURE_ROLE)
  {
    secondaryClubs = sec;
    numSharesPrimary = np;
    numSharesSecondary = ns;
    emit Configured (sec, np, ns);
  }

  /**
   * @dev Updates the referral bonus.
   */
  function setRefBonus (uint b, uint s) public onlyRole (CONFIGURE_ROLE)
  {
    /* We deliberately allow refBonusBps to be larger than refBonusBase
       (at least in theory), as that is a scenario that might still
       make sense (is at least not completely out of the question).  */
    refBonusBps = b;
    refBonusSeconds = s;
    emit RefBonusUpdated (b, s);
  }

  /**
   * @dev Updates the SMC mint rate (per unit of the payment token, e.g. USD).
   */
  function setSmcMintRate (uint r) public onlyRole (CONFIGURE_ROLE)
  {
    smcMintedPerUsd = r;
    emit SmcMintRateUpdated (r);
  }

  /**
   * @dev Configures the pricing curve.
   */
  function setPricing (PricingStep[] calldata p)
      public onlyRole (CONFIGURE_ROLE)
  {
    delete pricing;
    uint available = 0;

    for (uint i = 0; i < p.length; ++i)
      {
        available += p[i].num;
        pricing.push (p[i]);
      }

    totalSharesAvailable = available;
    require (totalSharesAvailable <= minter.shareSupply (),
             "more shares configured in pricing than are available");

    emit PricingUpdated (p);
  }

  /**
   * @dev Returns the full, current pricing curve.
   */
  function getPricing () public view returns (PricingStep[] memory)
  {
    return pricing;
  }

  /**
   * @dev Sets the sanctions oracle contract.
   */
  function setSanctionsList (ISanctionsList newList)
      public onlyRole (CONFIGURE_ROLE)
  {
    sanctionsList = newList;
    emit SanctionsListUpdated (newList);
  }

  /**
   * @dev Sets the KYC threshold.
   */
  function setKycThreshold (uint newThreshold) public onlyRole (CONFIGURE_ROLE)
  {
    kycThreshold = newThreshold;
    emit KycThresholdUpdated (newThreshold);
  }

  /**
   * @dev Adds a club to this tier.
   */
  function addClubInternal (uint clubId) internal
  {
    require (clubIndices[clubId] == 0, "club is already configured");

    clubIds.push (clubId);
    clubIndices[clubId] = clubIds.length;

    emit ClubAdded (clubId);
  }

  /**
   * @dev Adds a club to this tier.
   */
  function addClub (uint clubId) public onlyRole (CONFIGURE_ROLE)
  {
    addClubInternal (clubId);
  }

  /**
   * @dev Batch adds multiple clubs at once.
   */
  function addClubs (uint[] calldata ids) public onlyRole (CONFIGURE_ROLE)
  {
    for (uint i = 0; i < ids.length; ++i)
      addClubInternal (ids[i]);
  }

  /**
   * @dev Removes a club from the config.
   */
  function removeClubInternal (uint clubId) internal
  {
    uint indexPlusOne = clubIndices[clubId];
    require (indexPlusOne > 0, "the club does not exist");

    /* If the club is not currently at the end of the array, swap it there.  */
    if (indexPlusOne < clubIds.length)
      {
        uint endClubId = clubIds[clubIds.length - 1];
        clubIds[indexPlusOne - 1] = endClubId;
        clubIndices[endClubId] = indexPlusOne;
      }

    /* Now just remove the last entry, and the club index entry.  */
    clubIndices[clubId] = 0;
    clubIds.pop ();

    emit ClubRemoved (clubId);
  }

  /**
   * @dev Removes a club from the config.
   */
  function removeClub (uint clubId) public onlyRole (CONFIGURE_ROLE)
  {
    removeClubInternal (clubId);
  }

  /**
   * @dev Pauses the sale of a club.  This is used internally
   * by the minting process if a club is found to be sold out.
   */
  function pauseClubSaleInternal (uint clubId) internal
  {
    removeClubInternal (clubId);
    pausedClubs.push (clubId);
    emit ClubSalePaused (clubId);
  }

  /**
   * @dev Unpauses the sale of (up to) N paused clubs.  The number of
   * clubs actually unpaused is returned.
   */
  function unpauseClubSales (uint n)
      public onlyRole (CONFIGURE_ROLE) returns (uint)
  {
    uint unpaused = 0;
    while (pausedClubs.length > 0 && unpaused < n)
      {
        uint clubId = pausedClubs[pausedClubs.length - 1];
        addClubInternal (clubId);
        pausedClubs.pop ();
        ++unpaused;
        emit ClubSaleUnpaused (clubId);
      }

    return unpaused;
  }

  /**
   * @dev Returns the clubs (IDs) associated to this tier.
   */
  function getAllClubs () public view returns (uint[] memory)
  {
    return clubIds;
  }

  /**
   * @dev Returns the number of clubs in this tier.
   */
  function getNumClubs () public view returns (uint)
  {
    return clubIds.length;
  }

  /**
   * @dev Returns a slice of the array of all clubs.  This can be used
   * instead of getAllClubs() for the largest tier, where the full list of
   * clubs may be too long to be returned in a single call.
   */
  function getClubsSlice (uint start, uint len)
      public view returns (uint[] memory res)
  {
    if (start >= clubIds.length)
      return new uint[] (0);

    if (start + len > clubIds.length)
      len = clubIds.length - start;

    res = new uint[] (len);
    for (uint i = 0; i < len; ++i)
      res[i] = clubIds[i + start];
  }

  /**
   * @dev Returns the IDs of all clubs which have been paused.
   */
  function getPausedClubs () public view returns (uint[] memory)
  {
    return pausedClubs;
  }

  /**
   * @dev Updates the random seed to a new value, which is based on the
   * last block hash (so it is not easily manipulatable or predictable
   * even by the admin who can trigger this).
   */
  function updateSeedInternal () internal
  {
    seed = keccak256 (abi.encodePacked (
        "Soccerverse pack-sale seed",
        tier,
        blockhash (block.number - 1)
    ));
    emit SeedUpdated (seed);
  }

  /**
   * @dev Public version of updateSeedInternal, which can be called by
   * anyone with the appropriate role.
   */
  function updateSeed () public onlyRole (UPDATE_SEED_ROLE)
  {
    updateSeedInternal ();
  }

  /* ************************************************************************ */

  /**
   * @dev Helper function to return the number of shares that can still
   * be minted for the given club by the sale, based on the configured
   * pricing/availability curve.
   */
  function sharesAvailable (uint clubId) public view returns (uint)
  {
    uint total = totalSharesAvailable;
    uint minted = minter.sharesMinted (clubId);
    if (minted >= total)
      return 0;

    return total - minted;
  }

  /**
   * @dev Helper function to return the minimum of the passed-in number
   * (requested shares of some club) and the available shares (based on
   * what is configured in the pricing curve).
   */
  function sharesToGive (uint clubId, uint num) public view returns (uint)
  {
    uint available = sharesAvailable (clubId);
    return (available < num ? available : num);
  }

  /**
   * @dev Helper function to compute the total cost (in payment token
   * base units) for minting the next num shares of the given club, based
   * on the pricing curve we have.
   */
  function costOfNextShares (uint clubId, uint num) public view returns (uint)
  {
    uint res = 0;
    uint minted = minter.sharesMinted (clubId);

    for (uint i = 0; i < pricing.length; ++i)
      {
        uint cur = pricing[i].num;

        if (minted >= cur)
          {
            minted -= cur;
            continue;
          }
        if (minted > 0)
          {
            cur -= minted;
            minted = 0;
          }

        if (cur >= num)
          {
            res += pricing[i].price * num;
            num = 0;
            break;
          }

        res += pricing[i].price * cur;
        num -= cur;
      }

    require (num == 0, "not enough shares available");
    return res;
  }

  /**
   * @dev Helper function to compute the number of SMC minted for the given
   * total payment in base units of the payment token.
   */
  function smcToMintForPayment (uint paid) public view returns (uint)
  {
    uint factor = 10 ** token.decimals ();
    return (paid * smcMintedPerUsd) / factor;
  }

  /**
   * @dev Possible result of a buying approval check.
   */
  enum ApprovalCheckResult
  {

    /** @dev The purchase can go through.  */
    Ok,

    /** @dev The buyer address is sanctioned.  */
    Sanctioned,

    /** @dev The buyer needs to go through KYC first.  */
    KycNeeded

  }

  /**
   * @dev Checks if the given address and receiver account pair is allowed to
   * purchase packs with the given total value.  This checks sanctions
   * and the KYC/AML status as applicable.
   */
  function checkPurchaseApproval (address buyer, string calldata /*recipient*/,
                                  uint cost)
      public view returns (ApprovalCheckResult)
  {
    if (address (sanctionsList) != address (0)
          && sanctionsList.isSanctioned (buyer))
      return ApprovalCheckResult.Sanctioned;

    PurchaseTracker.Data memory data = purchaseTracker.getData (buyer);
    if (!data.approved && data.total + cost >= kycThreshold)
      return ApprovalCheckResult.KycNeeded;

    return ApprovalCheckResult.Ok;
  }

  /* ************************************************************************ */

  /**
   * @dev Data about the minting of an individual club as part of a full
   * pack mint.
   */
  struct ClubMint
  {

    /** @dev The club's ID.  */
    uint clubId;

    /** @dev How many shares are given in that club.  */
    uint numShares;

  }

  /**
   * @dev Details about a potential mint:  This contains explicitly the total
   * cost to be paid by the user, and all the shares they will get.  This can be
   * filled-in by "preview", and then the user should pass it back to the
   * "mint" routine.  This way, we ensure that what the user gets is what
   * they signed up for in every case, even if prices or availability of
   * shares might have changed (or, in that case, the transaction reverts
   * without costing the user anything).
   *
   * The struct also contains the "input data" for preview used, so that
   * it explicitly states what it is supposed to be, and future calls to
   * mint or for checking if it is still current don't need this data
   * explicitly passed in again.
   */
  struct PackMint
  {

    /** @dev The ID of the primary club for this mint.  */
    uint primaryClubId;

    /** @dev The number of packs bought.  */
    uint numPacks;

    /** @dev The total cost (in base units of the payment token).  */
    uint cost;

    /** @dev SMC minted to the primary club.  */
    uint smcMint;

    /** @dev All the club shares given out.  */
    ClubMint[] shares;

    /**
     * @dev A list of clubs that have been found as sold out during the
     * preview.  This list is provided as a hint (but not trusted) to the
     * minting process, where clubs that are found to be really sold out
     * will be "paused".
     */
    uint[] soldOut;

  }

  /**
   * @dev Returns the maximum number of packs that can be minted from this
   * tier for the given primary club, based on available shares.
   */
  function getMaxPacks (uint clubId) public view returns (uint)
  {
    if (paused ())
      return 0;

    if (payee == address (0))
      return 0;

    if (clubIndices[clubId] == 0)
      return 0;

    if (numSharesPrimary == 0)
      return 0;

    uint available = sharesAvailable (clubId);
    if (available == 0)
      return 0;

    if (available < numSharesPrimary)
      {
        /* In this case, some shares are available, but not enough to fill
           a pack.  We do still allow minting one pack, which will contain all
           the available shares of the primary club.  */
        return 1;
      }

    return available / numSharesPrimary;
  }

  /**
   * @dev Computes the PackMint data, based the current state, for minting
   * the given number of packs with the given primary club.
   */
  function preview (uint clubId, uint numPacks)
      public view returns (PackMint memory res)
  {
    uint primaryIndex = clubIndices[clubId];
    require (primaryIndex > 0, "primary club is not part of this tier");
    --primaryIndex;

    uint num = sharesToGive (clubId, numSharesPrimary * numPacks);
    require (num > 0, "no shares to give out in the primary club");
    require (num == numSharesPrimary * numPacks || numPacks == 1,
             "primary club is near sold out, only one pack can be bought");

    /* We limit the number of total iterations in the loop choosing
       secondary clubs to ensure we have an overall limit on gas.  In the
       typical case with far more clubs available than what we try to pick,
       this limit won't be hit.  But it ensures that there is some limit
       in edge cases, e.g. most clubs sold out and only few in the list
       of clubs at all (so many repetitions of clubs already seen).  */
    uint maxIterations = 20;
    require (secondaryClubs <= maxIterations, "maxIterations too small");

    /* We only know the maximum number of clubs in which shares might be given
       out, but not the actual, as some might be sold out.  Since we can't
       resize memory arrays, we first allocate one with maximum size here,
       and then after getting all the clubs into it, we copy the data over
       to the final array part of res.  */
    ClubMint[] memory shares = new ClubMint[] (1 + secondaryClubs);
    uint[] memory soldOut = new uint[] (maxIterations);

    /* While iterating secondary clubs, we keep track of all the clubs
       that have been seen already, to avoid duplicates (including the
       primary club).  This is implemented with a BoolSet (bit vector)
       on the indices into the clubIds array (rather than the club IDs
       themselves).  */
    BoolSet.Type memory clubsChecked = BoolSet.create (clubIds.length);
    clubsChecked.setTrue (primaryIndex);

    res.primaryClubId = clubId;
    res.numPacks = numPacks;
    res.cost = 0;

    shares[0] = ClubMint ({
      clubId: clubId,
      numShares: num
    });
    res.cost += costOfNextShares (clubId, num);

    /* The number of shares actually added to the shares array already.  If
       a secondary club we try is sold out, then this number does not get
       incremented, and so it may end up lower than 1 + secondaryClubs
       in the end.  */
    uint numShares = 1;
    uint numSoldOut = 0;

    /* To generate a pseudo-random list of secondary clubs, we use
       an in-memory seed initialised from the base seed (and clubId)
       and just hash it repeatedly to get more pseudo-random numbers.

       We then just use modulo to convert it into a club ID.  This has a
       slight bias towards lower numbers, but since the number of clubs is
       very small compared to the maximum uint256 value, that bias is
       negligible in practice.  */
    uint256 nextSeed = uint256 (keccak256 (abi.encodePacked (seed, clubId)));

    uint secondarySharesRequested = numSharesSecondary * numPacks;
    uint iterations = 0;
    uint secondaryTried = 0;
    if (secondarySharesRequested > 0)
      while (numShares < 1 + secondaryClubs
                && 1 + secondaryTried < clubIds.length
                && iterations < maxIterations)
        {
          uint secIndex = nextSeed % clubIds.length;
          uint secId = clubIds[secIndex];
          nextSeed = uint256 (keccak256 (abi.encodePacked (nextSeed)));
          ++iterations;

          /* We produce new seeds until we find a club we have not yet
             seen.  Since the number of secondary clubs is small compared
             to the total number of clubs in the tier, this is fine and should
             not cause too many extra iterations.  */
          if (clubsChecked.get (secIndex))
            continue;

          clubsChecked.setTrue (secIndex);

          /* When a club is found that we have not yet processed, independent
             of being sold out or not, we count it (as part of secondaryTried).
             If we have seen all clubs that there are, e.g. when most are sold
             out, then we exit the loop even if we have not yet found the number
             of clubs that has been requested to avoid an infinite loop.  */

          num = sharesToGive (secId, secondarySharesRequested);
          if (num > 0)
            {
              shares[numShares] = ClubMint ({
                clubId: secId,
                numShares: num
              });
              res.cost += costOfNextShares (secId, num);
              ++numShares;
            }
          if (num < secondarySharesRequested)
            {
              soldOut[numSoldOut] = secId;
              ++numSoldOut;
            }

          ++secondaryTried;
        }

    res.shares = new ClubMint[] (numShares);
    for (uint i = 0; i < numShares; ++i)
      res.shares[i] = shares[i];

    res.soldOut = new uint[] (numSoldOut);
    for (uint i = 0; i < numSoldOut; ++i)
      res.soldOut[i] = soldOut[i];

    res.smcMint = smcToMintForPayment (res.cost);
  }

  /**
   * @dev Checks if the current state for minting matches the PackMint
   * data provided.
   */
  function isPackMintCurrent (PackMint calldata mintData)
      public view returns (bool)
  {
    PackMint memory current = preview (mintData.primaryClubId,
                                       mintData.numPacks);

    if (current.cost != mintData.cost || current.smcMint != mintData.smcMint)
      return false;

    if (current.shares.length != mintData.shares.length)
      return false;

    /* Note that this only passes through if the order of share mints
       is the same.  So it might be that it fails even though in theory the
       mint arrays are equivalent, but that is fine and users need to make sure
       to pass in the original PackMint data without reordering.  */
    for (uint i = 0; i < current.shares.length; ++i)
      {
        if (current.shares[i].clubId != mintData.shares[i].clubId)
          return false;
        if (current.shares[i].numShares != mintData.shares[i].numShares)
          return false;
      }

    /* The soldOut array does not matter, as it is just a hint anyway,
       and will be checked before actually removing clubs.  */

    return true;
  }

  /**
   * @dev Internal function for minting packs.  This is called from the public
   * mint(), but can also be used internally together with auto-convert
   * in a subcontract.  This function checks the PackMint data that is passed
   * in and mints the packs, but does not take any payment.  So the publicly
   * exposed callers need to make sure to take payment accordingly.
   */
  function mintInternal (PackMint calldata mintData,
                         string calldata receiver, address buyer)
      internal
  {
    require (isPackMintCurrent (mintData),
             "provided PackMint data is no longer valid");

    require (checkPurchaseApproval (buyer, receiver, mintData.cost)
                == ApprovalCheckResult.Ok,
             "not allowed to purchase");

    for (uint i = 0; i < mintData.shares.length; ++i)
      minter.mintShares (
          mintData.shares[i].clubId, mintData.shares[i].numShares, receiver);

    /* Remove sold-out clubs after minting, so that clubs that are just now
       minted out are confirmed as sold out.  */
    for (uint i = 0; i < mintData.soldOut.length; ++i)
      {
        uint toRemove = mintData.soldOut[i];
        uint available = sharesAvailable (toRemove);
        if (available == 0)
          pauseClubSaleInternal (toRemove);
      }

    purchaseTracker.increment (buyer, receiver, mintData.cost);

    emit PacksBought (buyer, receiver,
                      mintData.primaryClubId, mintData.numPacks,
                      mintData.cost);

    /* Give the referral bonus if we can.  */
    (ReferralTracker.RefData memory ref, bool hasReferrer)
        = refTracker.maybeGetReferrer (receiver);
    if (hasReferrer && ref.timestamp + refBonusSeconds >= block.timestamp)
      {
        uint refClub = mintData.primaryClubId;
        assert (mintData.shares.length > 0);
        assert (refClub == mintData.shares[0].clubId);

        uint refShares = (mintData.shares[0].numShares * refBonusBps)
                            / refBonusBase;
        uint refGiven = sharesToGive (refClub, refShares);

        if (refGiven > 0)
          {
            minter.mintShares (refClub, refGiven, ref.referrer);
            emit ReferralBonusGiven (receiver, ref.referrer, refClub, refGiven,
                                     mintData.numPacks, mintData.cost);

            if (refGiven < refShares)
              {
                assert (sharesAvailable (refClub) == 0);
                pauseClubSaleInternal (refClub);
              }
          }
      }

    /* Mint SMC for the primary club.  */
    if (mintData.smcMint > 0)
      minter.mintClubSmc (mintData.primaryClubId, mintData.smcMint);
  }

  /**
   * @dev Requests to mint one or more packs.  Payment is taken from the
   * _msgSender(), and the minted shares will be given to the receiver account
   * name.
   */
  function mint (PackMint calldata mintData, string calldata receiver)
      public whenNotPaused
  {
    require (payee != address (0), "no payee configured");

    address buyer = _msgSender ();
    if (mintData.cost > 0)
      require (token.transferFrom (buyer, payee, mintData.cost),
               "failed to transfer payment");

    mintInternal (mintData, receiver, buyer);
  }

  /* ************************************************************************ */

}
