#!/usr/bin/env python3
# Copyright (C) 2024 Soccerverse Ltd

"""
Python script to test the SwapperV2V3 contract on a network forked
from a real one (with all Uniswap infrastructure) with Anvil.
"""

import const
import subpaths

from eth_account import Account
import jsonrpclib
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

import argparse
import json
import logging
import os.path
import sys

# Addresses of some holders of tokens, which we can use to
# get balances from with impersonation.
TOKEN_HOLDERS = {
  const.USDC: "0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD",
  const.WCHI: "0x2ADCbe31a816897FaDaD6d61c9a9Fcfb9254B823",
  const.WETH: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8",
}

################################################################################

class Tester:
  """
  Main class handling the SwapperV2V3 testing.
  """

  def __init__ (self, rpcUrl, token):
    self.log = logging.getLogger ("")
    self.exactToken = token

    self.w3 = Web3 (Web3.HTTPProvider (rpcUrl))
    self.w3.middleware_onion.inject (ExtraDataToPOAMiddleware, layer=0)
    self.log.info ("Connected to chain %d" % self.w3.eth.chain_id)

    rpcConfig = jsonrpclib.config.DEFAULT
    rpcConfig.content_type = "application/json"
    self.rpc = jsonrpclib.ServerProxy (rpcUrl, config=rpcConfig)
    self.rpc.hardhat_autoImpersonateAccount (True)

    # We use debugging methods (such as account impersonation) to send
    # transactions, so we do not need an actual private key.  But we generate
    # a random new address to use in the test.
    self.testAddress = Account.create ().address
    self.log.info ("Using test address: %s" % self.testAddress)

    swapper = self.loadContract ("SwapperV2V3")
    receipt = self.sendTx (swapper.constructor (token))

    self.swapper = self.loadContract ("SwapperV2V3",
                                      addr=receipt.contractAddress)
    self.log.info ("Deployed SwapperV2V3 at %s" % self.swapper.address)

  def loadContract (self, nm, addr=None):
    """
    Constructs a web3 Contract instance with the data (such as ABI
    and bytecode) from the given name.  If addr is set, then it is used
    as the address.  Otherwise, we initialise an instance with the bytecode,
    so it can be deployed afterwards.
    """

    baseDir = os.path.dirname (os.path.abspath (__file__))
    outDir = os.path.join (baseDir, "..", "..", "out", f"{nm}.sol")
    with open (os.path.join (outDir, f"{nm}.json"), "rt") as f:
      data = json.load (f)

    if addr is None:
      return self.w3.eth.contract (abi=data["abi"],
                                   bytecode=data["bytecode"]["object"])

    return self.w3.eth.contract (abi=data["abi"], address=addr)

  def sendTx (self, call, sender=None):
    """
    Sends a call and waits for it to be confirmed.
    """

    if sender is None:
      sender = self.testAddress

    # Ensure we can pay gas.
    self.rpc.hardhat_setBalance (sender, "0x%x" % (100 * 10**18))

    txid = call.transact ({"from": sender})
    return self.w3.eth.wait_for_transaction_receipt (txid)

  def clearTokens (self, tokens=[const.USDC, const.WCHI, const.WETH]):
    """
    Sets the balances of the given tokens for the swapper contract
    to zero.
    """

    addr = self.swapper.address

    for t in tokens:
      c = self.loadContract ("IERC20", addr=t)
      bal = c.functions.balanceOf (addr).call ()
      if bal > 0:
        self.sendTx (c.functions.transfer (TOKEN_HOLDERS[t], bal),
                     sender=addr)

  def getToken (self, token):
    """
    Adds a (large) balance of the given token to the swapper contract
    address and returns the total given.
    """

    sender = TOKEN_HOLDERS[token]

    c = self.loadContract ("IERC20", addr=token)
    amount = c.functions.balanceOf (sender).call () // 2
    self.sendTx (c.functions.transfer (self.swapper.address, amount),
                 sender=sender)

    return amount

  def getBalance (self, token):
    """
    Returns the swapper contract's balance of a token.
    """

    c = self.loadContract ("IERC20", addr=token)
    return c.functions.balanceOf (self.swapper.address).call ()

  def getInputOutputTokens (self, subp):
    """
    Returns the initial input and ultimate output tokens for a given
    path (encoded as subpaths).
    """

    parts = subpaths.decode (subp)

    (inp, _) = self.swapper.functions.getSubpathTokens (parts[0]).call ()
    (_, outp) = self.swapper.functions.getSubpathTokens (parts[-1]).call ()

    inp = self.w3.to_checksum_address (inp)
    outp = self.w3.to_checksum_address (outp)

    return inp, outp

  def formatToken (self, amount, token):
    """
    Formats a token amount with decimals and symbol.
    """

    c = self.loadContract ("IERC20Metadata", token)
    sym = c.functions.symbol ().call ()
    dec = c.functions.decimals ().call ()

    value = amount / 10.0**dec

    return "%.4f %s" % (value, sym)

  def testQuoteExactInput (self, amount, subp):
    """
    Runs a quoteExactInput with the given input amount along the given
    path.  Returns the final output amount, and prints a log with the
    details.
    """

    (inp, outp) = self.getInputOutputTokens (subp)
    assert inp == self.exactToken
    quote = self.swapper.functions.quoteExactInput (amount, outp, subp).call ()

    inputStr = self.formatToken (amount, inp)
    outputStr = self.formatToken (quote, outp)

    self.log.info ("Quote exact input: %s to %s" % (inputStr, outputStr))

    return quote

  def testQuoteExactOutput (self, amount, subp):
    """
    Runs a quoteExactOutput with the given output amount along the given
    path.  Returns the final input amount, and prints a log with the
    details.
    """

    (inp, outp) = self.getInputOutputTokens (subp)
    assert outp == self.exactToken
    quote = self.swapper.functions.quoteExactOutput (inp, amount, subp).call ()

    inputStr = self.formatToken (quote, inp)
    outputStr = self.formatToken (amount, outp)

    self.log.info ("Quote exact output: %s to %s" % (inputStr, outputStr))

    return quote

  def testSwapExactInput (self, amount, subp):
    """
    Runs an actual swap with swapExactInput for the given input amount
    and the path.  The exact input token will be retrieved into the swapper
    balance beforehand.  Logs will be printed, and the amount retrieved
    will be returned.
    """

    (inp, outp) = self.getInputOutputTokens (subp)
    assert inp == self.exactToken

    self.clearTokens ()
    initialBalance = self.getToken (inp)

    self.sendTx (self.swapper.functions.swapExactInput (amount, outp, subp))

    sent = initialBalance - self.getBalance (inp)
    received = self.getBalance (outp)

    inputStr = self.formatToken (sent, inp)
    outputStr = self.formatToken (received, outp)

    self.log.info ("Exact input swap: %s to %s" % (inputStr, outputStr))

    assert sent == amount

    return received

  def testSwapExactOutput (self, amount, subp):
    """
    Runs an actual swap with swapExactOutput for the given input
    amount and path.  The amount sent will be returned.
    """

    (inp, outp) = self.getInputOutputTokens (subp)
    assert outp == self.exactToken

    self.clearTokens ()
    initialBalance = self.getToken (inp)

    self.sendTx (self.swapper.functions.swapExactOutput (inp, amount, subp))

    sent = initialBalance - self.getBalance (inp)
    received = self.getBalance (outp)

    inputStr = self.formatToken (sent, inp)
    outputStr = self.formatToken (received, outp)

    self.log.info ("Exact output swap: %s to %s" % (inputStr, outputStr))

    # It seems the quote is not always fully exact (but surely an upper bound)
    # for the real input required to get a certain amount of output.  That is
    # fine, as the difference is minor, and the user will have accepted the
    # input amount anyway.  In a real-life situation, there will be slippage
    # anyway, and the excess will be rolled into the burn fee.
    assert received >= amount

    return sent

################################################################################

if __name__ == "__main__":
  logging.basicConfig (stream=sys.stderr, level=logging.INFO)

  desc = "Test SwapperV2V3 on a real or forked network"
  parser = argparse.ArgumentParser (description=desc)
  parser.add_argument ("--eth_rpc_url", default="http://localhost:8545",
                       help="URL for the EVM JSON-RPC interface to use")
  args = parser.parse_args ()

  t = Tester (args.eth_rpc_url, const.WCHI)

  c = subpaths.Constructor (const.WCHI)
  c.addV2 (const.WETH)
  c.addV3 ((500, const.USDC))
  wchiToUsdc = c.encode ()

  c = subpaths.Constructor (const.USDC)
  c.addV3 ((500, const.WETH))
  c.addV2 (const.WCHI)
  usdcToWchi = c.encode ()

  t.testQuoteExactInput (10**8, wchiToUsdc)
  t.testQuoteExactInput (100 * 10**8, wchiToUsdc)
  quote = t.testQuoteExactInput (10000 * 10**8, wchiToUsdc)
  received = t.testSwapExactInput (10000 * 10**8, wchiToUsdc)
  assert quote == received

  t.testQuoteExactOutput (10**8, usdcToWchi)
  t.testQuoteExactOutput (100 * 10**8, usdcToWchi)
  quote = t.testQuoteExactOutput (10000 * 10**8, usdcToWchi)
  sent = t.testSwapExactOutput (10000 * 10**8, usdcToWchi)
  assert quote == sent
