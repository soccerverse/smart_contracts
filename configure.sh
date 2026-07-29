#!/bin/sh -e
GAMEID="${GAMEID:-sv}"
sed "s/@GAMEID@/${GAMEID}/g" src/Config.sol.in > src/Config.sol
echo "Configured for game ID: g/${GAMEID}"
