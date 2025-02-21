#!/usr/bin/env python3
# Copyright (C) 2024 Soccerverse Ltd

"""
This script queries for and displays all the access roles and permissions
configured on the important contracts for Soccerverse.
"""

from web3 import Web3

import argparse
import json
import logging
import os.path
import sys

################################################################################

class PermissionsChecker:
  """
  Worker class to handle permission checking.
  """

  def __init__ (self, rpcUrl):
    logging.basicConfig (stream=sys.stderr, level=logging.INFO)
    self.log = logging.getLogger ("")

    self.w3 = Web3 (Web3.HTTPProvider (args.eth_rpc_url))
    self.log.info ("Connected to chain %d" % self.w3.eth.chain_id)

  def getContract (self, nm, addr):
    """
    Loads an ABI file and instantiates the contract instance
    for this ABI and the given address.
    """

    baseDir = os.path.dirname (os.path.abspath (__file__))
    abiDir = os.path.join (baseDir, "out", f"{nm}.sol")
    abiFile = os.path.join (abiDir, f"{nm}.json")
    with open (abiFile, "rt") as f:
      data = json.load (f)

    return self.w3.eth.contract (abi=data["abi"], address=addr)

  def logRoleMembers (self, c, nm):
    """
    Queries for and prints all addresses that have a given role (as string).
    """

    role = getattr (c.functions, nm) ().call ()
    num = c.functions.getRoleMemberCount (role).call ()
    self.log.info ("  %s has %d members:" % (nm, num))

    for ind in range (num):
      addr = c.functions.getRoleMember (role, ind).call ()
      self.log.info ("    %s" % addr)

  def checkClubMinter (self, addr):
    c = self.getContract ("ClubMinter", addr)
    self.log.info ("ClubMinter at %s:" % c.address)
    self.logRoleMembers (c, "DEFAULT_ADMIN_ROLE")
    self.logRoleMembers (c, "MINTER_ROLE")

  def checkPurchaseTracker (self, addr):
    c = self.getContract ("PurchaseTracker", addr)
    self.log.info ("PurchaseTracker at %s:" % c.address)
    self.logRoleMembers (c, "DEFAULT_ADMIN_ROLE")
    self.logRoleMembers (c, "APPROVER_ROLE")
    self.logRoleMembers (c, "INCREMENT_TOTAL_ROLE")

  def checkPackVoucher (self, addr):
    c = self.getContract ("PackVoucher", addr)
    self.log.info ("PackVoucher at %s:" % c.address)
    self.logRoleMembers (c, "DEFAULT_ADMIN_ROLE")
    self.logRoleMembers (c, "TOKEN_ADMIN_ROLE")
    self.logRoleMembers (c, "BURNER_ROLE")
    self.logRoleMembers (c, "LIMITED_MINTER_ROLE")

  def checkSwappingPackSale (self, addr):
    c = self.getContract ("SwappingPackSale", addr)
    tier = c.functions.tier ().call ()
    self.log.info ("SwappingPackSale '%s' at %s:" % (tier, c.address))
    self.logRoleMembers (c, "DEFAULT_ADMIN_ROLE")
    self.logRoleMembers (c, "CONFIGURE_ROLE")
    self.logRoleMembers (c, "UPDATE_SEED_ROLE")

  def checkDemocrit (self, addr):
    dem = self.getContract ("DemocritSoccerverse", addr)
    acAddr = dem.functions.autoConvertAddress ().call ()
    ac = self.getContract ("AutoConvert", acAddr)

    self.log.info ("DemocritSoccerverse at %s:" % dem.address)
    self.log.info ("  owner: %s" % dem.functions.owner ().call ())

    self.log.info ("AutoConvert at %s:" % ac.address)
    self.log.info ("  owner: %s" % ac.functions.owner ().call ())

################################################################################

if __name__ == "__main__":
  desc = "Checks permissions on Soccerverse contracts"
  parser = argparse.ArgumentParser (description=desc)
  parser.add_argument ("--eth_rpc_url", default="https://polygon-rpc.com",
                       help="URL for the EVM JSON-RPC interface to use")
  args = parser.parse_args ()

  checker = PermissionsChecker (args.eth_rpc_url)

  checker.checkDemocrit ("0xEB265D9fBb05641266366F15EcE76a268EF4a2A4")

  checker.checkClubMinter ("0xeEE0d855112b71Dc68d72053594Af03F92C586Ae")
  checker.checkPurchaseTracker ("0x879E44f2025cAd323f8F1C7C28F672F5f3f92304")
  checker.checkPackVoucher ("0x9De075D87B812eC647d5541CB50d65Bc06Ec6509")

  checker.checkSwappingPackSale ("0x8501A9018A5625b720355A5A05c5dA3D5E8bB003")
  checker.checkSwappingPackSale ("0x0bF818f3A69485c8B05Cf6292D9A04C6f58ADF08")
  checker.checkSwappingPackSale ("0x4259D89087b6EBBC8bE38A30393a2F99F798FE2f")
  checker.checkSwappingPackSale ("0x167360A54746b82e38f700dF0ef812c269c4e565")
  checker.checkSwappingPackSale ("0x3d25Cb3139811c6AeE9D5ae8a01B2e5824b5dB91")
