AC_INIT([sv-smartcontracts], [1.0])
AM_INIT_AUTOMAKE

# The game ID to use in the smart contracts.  This is g/sv for production,
# and g/svt for development / testing.
AC_ARG_VAR(GAMEID, "the game ID to set in the contracts")
GAMEID="${GAMEID:-sv}"

AM_SILENT_RULES([yes])

AC_SUBST(GAMEID)
AC_DEFINE_UNQUOTED([GAMEID], "${GAMEID}", [The game ID used in the GSP])

AC_CONFIG_FILES([
  Makefile \
  src/Config.sol
])
AC_OUTPUT

echo
echo "Configured for game ID: g/${GAMEID}"
