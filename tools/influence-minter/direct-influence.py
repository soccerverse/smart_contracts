#!/usr/bin/env python3

# Script to mint club influence in Soccerverse based on a direct list of
# receiver accounts and influence they should get.  This is used for initial
# allocations to investors or for promos.

from minter import InfluenceMinter

import argparse
import csv

parser = argparse.ArgumentParser ()
parser.add_argument ("--eth_rpc_url", required=True,
                     help="JSON-RPC endpoint for the EVM chain")
parser.add_argument ("--gsp_rpc_url", required=True,
                     help="JSON-RPC endpoint for the matching GSP")
parser.add_argument ("input", help="Input CSV file to process")
args = parser.parse_args ()

minter = InfluenceMinter (args.eth_rpc_url, args.gsp_rpc_url)

with open (args.input, newline="") as csvfile:
  reader = csv.DictReader (csvfile)
  for row in reader:
    clubId = int (row["club_id"])
    amount = int (row["amount"])
    minter.mintClub (row["account"], clubId, amount)
minter.flush ()
