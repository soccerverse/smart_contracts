// SPDX-License-Identifier: MIT
// Copyright (C) 2024 Soccerverse Ltd

const truffleContract = require ("@truffle/contract");

const ReferralTracker = artifacts.require ("ReferralTracker");

module.exports = async function (deployer, network)
  {
    /* This script is for the real deployment.  Unit tests use custom deployment
       on a per-test basis as needed, so we want to skip deployment entirely
       for them.  */
    if (network === "test" || network === "soliditycoverage")
      return;

    await deployer.deploy (ReferralTracker);
  };
