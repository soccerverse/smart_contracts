# For successful execution, a worker address needs to hold gas and be
# configured as a MINTER_ROLE on the ClubMinter contract.
#
# The worker address' private key needs to be provided in the
# PRIVKEY environment variable.

import config

from eth_account import Account
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

import jsonrpclib

import json
import logging
import os
import sys
import time


DRY_RUN = True
IGNORE_EXISTING_BALANCE = True


class Web3Base:
  """
  Base class that just defines the web3 basics.
  """

  def __init__ (self, rpcUrl):
    logging.basicConfig (level=logging.INFO, stream=sys.stderr)
    self.log = logging.getLogger ()

    self.w3 = Web3 (Web3.HTTPProvider (rpcUrl))
    self.w3.middleware_onion.inject (ExtraDataToPOAMiddleware, layer=0)

    with open ("ClubMinter.json", "rt") as f:
      data = json.load (f)
    self.cm = self.w3.eth.contract (abi=data["abi"], address=config.CLUB_MINTER)
    self.log.info ("Using ClubMinter at %s" % self.cm.address)

  def setupAccount (self):
    """
    Sets up the Ethereum account to use as worker, based on the
    private key configured in the environment.
    """

    self.key = os.getenv ("PRIVKEY")
    if self.key is None:
      raise RuntimeError ("PRIVKEY must be set")
    self.acc = Account.from_key (self.key)
    self.log.info ("Worker address: %s" % self.acc.address)
    self.log.info ("Balance for gas: %.4f"
                    % (self.w3.eth.get_balance (self.acc.address) / 10.0**18))

    # We manage the nonce ourselves to avoid race conditions.
    self.nonce = self.w3.eth.get_transaction_count (self.acc.address)

  def sendTx (self, call):
    """
    Helper function to send a transaction with our worker address, based
    on a function call.  Gas is estimated automatically.  The txid is returned.
    """

    gas = call.estimate_gas ({"from": self.acc.address})
    tx = call.build_transaction ({
      "chainId": self.w3.eth.chain_id,
      "gas": gas,
      "type": 2,
      "maxFeePerGas": self.w3.to_wei (config.MAX_GAS_GWEI, "gwei"),
      "maxPriorityFeePerGas": self.w3.to_wei (config.PRIO_GAS_GWEI, "gwei"),
      "nonce": self.nonce,
    })

    signed = self.w3.eth.account.sign_transaction (tx, private_key=self.key)
    if DRY_RUN:
      txid = "dummy"
    else:
      txid = self.w3.eth.send_raw_transaction (signed.raw_transaction).hex ()
      self.w3.eth.wait_for_transaction_receipt (txid)

    self.nonce += 1

    return txid


class InfluenceMinter (Web3Base):
  """
  Base class for scripts that mint influence to certain users.
  """

  def __init__ (self, rpcUrl, gspUrl):
    super ().__init__ (rpcUrl)

    self.gsp = jsonrpclib.ServerProxy (gspUrl)

    # We record the starting block height.  We require the GSP to be synced
    # at least to this block before we accept its state (number of shares
    # already owned before running the script).
    self.startHeight = self.w3.eth.get_block ("latest")["number"]

    self.setupAccount ()
    # Check that the worker address has MINTER_ROLE.
    role = self.cm.functions.MINTER_ROLE ().call ()
    if not self.cm.functions.hasRole (role, self.acc.address).call ():
      raise RuntimeError ("Worker address is not MINTER_ROLE")

    # Query for the game ID.
    self.gameId = self.cm.functions.gameId ().call ()
    self.log.info ("Using game ID: %s" % self.gameId)

    # When a mint is requested, we add it to a list of queued mints,
    # and execute them in batch periodically.
    self.pendingMints = []

  def flush (self):
    """
    Processes all of the pending mints immediately.
    """

    if len (self.pendingMints) == 0:
      return

    call = self.cm.functions.batchMint (self.pendingMints)
    txid = self.sendTx (call)
    self.log.info ("Flushed batch of %d mints: %s"
                    % (len (self.pendingMints), txid))
    self.pendingMints = []

  def getClubOwnership (self, receiver, clubId):
    """
    Queries the GSP and returns the amount of influence owned by the receiver
    account name in the given club.
    """

    while True:
      data = self.gsp.get_user_share_balances (name=receiver)
      if data["gameid"] != self.gameId:
        raise RuntimeError ("Mismatch in game ID between GSP and ClubMinter")

      if data["height"] >= self.startHeight:
        shares = data["data"]
        break

      # Otherwise, wait a bit in the hope that the GSP catches up.
      time.sleep (0.1)

    for s in shares:
      if "club" in s["share"] and s["share"]["club"] == clubId:
        return s["balance"]["total"]

    return 0

  def mintClub (self, receiver, clubId, amount):
    """
    Mints club influence to a receiver account.  The GSP is queried first,
    and if the account already owns that club's influence, nothing is done
    (or an error raised in case the amount mismatches).  This ensures that
    a broken run can be resumed without double minting.
    """

    owned = self.getClubOwnership (receiver, clubId)
    if IGNORE_EXISTING_BALANCE:
      owned = 0

    if owned > 0:
      if owned > amount:
        self.log.warning (
            "User '%s' owns already %d (want %d) influence in club %d"
              % (receiver, owned, amount, clubId))
        return
      elif owned == amount:
        self.log.info ("User '%s' already has %d of club %d"
                        % (receiver, owned, clubId))
        return
      else:
        self.log.info ("User '%s' owns %d of club %d, minting the rest"
                        % (receiver, owned, clubId))
    amount -= owned
    assert amount > 0

    self.log.info ("Minting %d of club %d for '%s'"
                    % (amount, clubId, receiver))
    self.pendingMints.append ((clubId, amount, receiver, 0))
    if len (self.pendingMints) >= config.BATCH_SIZE:
      self.flush ()
