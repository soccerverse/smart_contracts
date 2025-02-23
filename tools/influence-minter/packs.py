#!/usr/bin/env python3

# Script to mint club influence in Soccerverse based on a list of user
# accounts, primary clubs and USD value owed.  This is used to give influence
# to testers (among others) based on their club preference in the beta,
# and for give-aways.
#
# The script determines how many packs of that primary club the user could
# buy with the USD amount (rounding up to be fair).  Those packs are then
# minted via the PackVoucher contract.

import config
from minter import Web3Base

import argparse
import csv
from decimal import Decimal
import json

parser = argparse.ArgumentParser ()
parser.add_argument ("--eth_rpc_url", required=True,
                     help="JSON-RPC endpoint for the EVM chain")
parser.add_argument ("input", help="Input CSV file to process")
args = parser.parse_args ()


IGNORE_MINTERS = set ([
  config.PACK_VOUCHER,
  "0x08813C466Ea41C18d604F1889971515614d773Be",
  "0x0C8D50F6996bfA35d8cAC9FDf82b74659aF90DD1",
])


def mintCost (mint):
  """
  Extracts the "cost" field of a PackMint struct returned
  from PackSale.preview.
  """

  return mint[2]


class PackMinter (Web3Base):
  """
  Extended minter class that adds support for minting based on
  packs and USD values owed.
  """

  def __init__ (self, rpcUrl):
    super ().__init__ (rpcUrl)

    with open ("PackVoucher.json", "rt") as f:
      data = json.load (f)
    self.voucher = self.w3.eth.contract (address=config.PACK_VOUCHER,
                                         abi=data["abi"])

    with open ("SwappingPackSale.json", "rt") as f:
      data = json.load (f)
    saleAbi = data["abi"]

    with open ("IERC20Metadata.json", "rt") as f:
      data = json.load (f)
    self.erc20abi = data["abi"]

    self.setupAccount ()
    # Check that we are LIMITED_MINTER_ROLE on the voucher contract.
    role = self.voucher.functions.LIMITED_MINTER_ROLE ().call ()
    if not self.voucher.functions.hasRole (role, self.acc.address).call ():
      raise RuntimeError ("Worker address is not LIMITED_MINTER_ROLE")

    # Extract the minters from the ClubMinter.  We assume those are
    # pack-sale contracts (which we use only to preview the packs)
    # and our own address.  This is then used to build up a mapping
    # between club IDs and the corresponding sales contract.
    #
    # The last tier has too many clubs to return in one call,
    # and we use it as fallback instead:  If a club is not set in
    # saleForClub, we assume it is for the fallback.
    self.saleForClub = {}
    self.fallback = None
    role = self.cm.functions.MINTER_ROLE ().call ()
    numMinters = self.cm.functions.getRoleMemberCount (role).call ()
    for i in range (numMinters):
      minter = self.cm.functions.getRoleMember (role, i).call ()
      if minter in IGNORE_MINTERS:
        continue
      contract = self.w3.eth.contract (abi=saleAbi, address=minter)
      try:
        clubs = contract.functions.getAllClubs ().call ()
        self.log.info ("Sale contract '%s' for %d clubs: %s"
                        % (contract.functions.tier ().call (),
                           len (clubs), minter))
        for c in clubs:
          self.saleForClub[c] = contract
      except:
        if self.fallback is not None:
          raise RuntimeError ("Duplicate fallback contract: %s" % minter)
        self.fallback = contract
        self.log.info ("Sale contract '%s' as fallback: %s"
                        % (contract.functions.tier ().call (), minter))

    # The current batch of RedeemOp's that is pending execution.  We also
    # track the total cost for it, so we can ensure we got enough voucher
    # tokens for it when sending.
    self.batchOps = []
    self.batchCost = 0

  def getContractForClub (self, clubId):
    """
    Returns the sales contract to use for the given club.
    """

    if clubId in self.saleForClub:
      return self.saleForClub[clubId]

    # If we use the fallback, check that the club is really at it.
    contract = self.fallback
    if contract.functions.clubIndices (clubId).call () == 0:
      raise RuntimeError ("Club %d is not at fallback sales contract" % clubId)

    return contract

  def packsForUsd (self, primaryClub, usdValue):
    """
    Computes how many packs of the given primaryClub can be purchased
    for the given usdValue, rounded up.
    """

    # We use a binary search to find the exact number of packs to buy.
    # To start off, we use one as lower bound (if that is already too much,
    # one it is).  The upper bound can be found by using the price of the
    # first pack as basis, since the price will go up, and thus in reality,
    # that will be an upper bound.

    c = self.getContractForClub (primaryClub)

    tkAddr = c.functions.token ().call ()
    tk = self.w3.eth.contract (abi=self.erc20abi, address=tkAddr)
    dec = tk.functions.decimals ().call ()
    value = int (usdValue * 10**dec)

    onePack = mintCost (c.functions.preview (primaryClub, 1).call ())
    if onePack >= value:
      return 1

    lower = 1
    upper = (value // onePack) + 1
    assert upper > lower

    while upper - lower > 1:
      mid = (upper + lower) // 2
      assert mid > lower and mid < upper

      midCost = mintCost (c.functions.preview (primaryClub, mid).call ())
      if midCost >= value:
        upper = mid
      else:
        lower = mid

    assert lower + 1 == upper
    return upper

  def mintPacks (self, receiver, primaryClub, usdValue):
    """
    Computes how many packs with a certain primary club can be bought
    with usdValue (rounding up), and then records the equivalent influence
    of those packs in our list of what should be minted.
    """

    numPacks = self.packsForUsd (primaryClub, usdValue)

    c = self.getContractForClub (primaryClub)
    data = c.functions.preview (primaryClub, numPacks).call ()

    shares = data[4]
    self.log.info ("Tester '%s' with value $%.2f:" % (receiver, usdValue))
    for clubId, amount in shares:
      self.log.info ("  %d in club %d" % (amount, clubId))

    self.batchOps.append ({
      "sale": c.address,
      "mintData": data,
      "receiver": receiver,
    })
    self.batchCost += mintCost (data)

    if len (self.batchOps) >= config.BATCH_SIZE:
      self.flush ()

  def flush (self):
    """
    Flushes the current pending batch of redeems.
    """

    if not self.batchOps:
      return

    self.log.info ("Flushing batch of %d redeem..." % len (self.batchOps))

    # Check that we have enough voucher tokens.  If not, try to mint more
    # for ourselves.
    balance = self.voucher.functions.balanceOf (self.acc.address).call ()
    if balance < self.batchCost:
      required = self.batchCost - balance
      dec = self.voucher.functions.decimals ().call ()
      self.log.info ("Minting %.2f tokens..." % (required / 10.0**dec))
      call = self.voucher.functions.mint (self.acc.address, required)
      txid = self.sendTx (call)
      self.log.info ("  %s" % txid)

    # Execute the batch itself.
    call = self.voucher.functions.batchRedeem (self.batchOps)
    txid = self.sendTx (call)
    self.log.info ("Executed batchRedeem: %s" % txid)

    self.batchOps = []
    self.batchCost = 0


minter = PackMinter (args.eth_rpc_url)

with open (args.input, "rt", newline="") as csvfile:
  reader = csv.DictReader (csvfile)
  for row in reader:
    clubId = int (row["primary_club"])
    usdValue = Decimal (row["usd_value"])
    minter.mintPacks (row["account"], clubId, usdValue)

minter.flush ()
