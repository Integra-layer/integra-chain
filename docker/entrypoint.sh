#!/bin/bash
set -e

case "$1" in
  setup)
    exec setup-wizard
    ;;
  start)
    exec intgd start \
      --home /root/.intgd \
      --minimum-gas-prices "5000000000000airl" \
      --json-rpc.enable true \
      --json-rpc.api "eth,txpool,personal,net,debug,web3"
    ;;
  *)
    exec "$@"
    ;;
esac
