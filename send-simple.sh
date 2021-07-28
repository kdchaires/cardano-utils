#!/usr/bin/env bash

# Get the source payment address (so we can use it in query utxo)
# PARAMS=""
PARAMS=()

while (( "$#" )); do
  case "$1" in
    -s|--source-address)
      SOURCE_ADDR="$2"
      shift
      shift
      ;;
    -f|--source-address-file)
      SOURCE_ADDR_FILE="$2"
      shift
      shift
      ;;
    -d|--destination-address)
      DEST_ADDR="$2"
      shift
      shift
      ;;
    -a|--amount)
      AMOUNT="$2"
      shift
      shift
      ;;
    -m|--magic-id)
      MAGIC_ID="$2"
      shift
      shift
      ;;
    -k|--signing-key-file)
      SKEY_FILE="$2"
      shift
      shift
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS+=($1)
      shift
      ;;
  esac
done

# Validate either a file with the addr was given or the addr itself
if [[ ! -f "$SOURCE_ADDR_FILE" && -z "$SOURCE_ADDR" ]]; then
  echo "Error: I need either the --source-address or the --source-address-file to be given." >&2
  exit 1
fi

# If a file was given we read it
if [[ -f "$SOURCE_ADDR_FILE" ]]; then
  SOURCE_ADDR=$(cat $SOURCE_ADDR_FILE)
fi

# tx-build -f payment.addr

# set positional arguments in their proper place
eval set -- "${PARAMS[@]}"

PROTOCOL_FILE="protocol.json"

# Get the protocol parameters
cardano-cli query protocol-parameters --testnet-magic $MAGIC_ID --out-file $PROTOCOL_FILE

# Get the Tx hash of the UTxO to spend
TX_HASH=$(cardano-cli query utxo --testnet-magic $MAGIC_ID --address $SOURCE_ADDR | tail -n1 | cut -d ' ' -f 1)

# Get the Ix of UTxO to spend
TX_IX=$(cardano-cli query utxo --testnet-magic $MAGIC_ID --address $SOURCE_ADDR | tail -n1 | awk '{ print $2 }')

UTXO_BALANCE=$(cardano-cli query utxo --testnet-magic $MAGIC_ID --address $SOURCE_ADDR | tail -n1 | awk '{ print $3 }')

TX_TMP_DRAFT="tx-tmp.draft"

# Draft the TX
cardano-cli transaction build-raw \
	--tx-in $TX_HASH#$TX_IX \
	--tx-out $DEST_ADDR+0 \
	--tx-out $SOURCE_ADDR+0 \
	--invalid-hereafter 0 \
	--fee 0 \
	--out-file $TX_TMP_DRAFT


# Calculate the fee
MIN_FEE=$(cardano-cli transaction calculate-min-fee \
	--tx-body-file $TX_TMP_DRAFT \
	--tx-in-count 1 \
	--tx-out-count 2 \
	--witness-count 1 \
	--testnet-magic $MAGIC_ID \
	--protocol-params-file $PROTOCOL_FILE | cut -d ' ' -f 1) 

# Calculate the change to send back (using expr)
# expr <UTXO BALANCE> - <AMOUNT TO SEND> - <TRANSACTION FEE>
CHANGE=$(expr $UTXO_BALANCE - $AMOUNT - $MIN_FEE)

# Build the transaction
$TX_RAW="tx.raw"
cardano-cli transaction build-raw \
 	--fee $MIN_FEE \
 	--tx-in $TX_HASH#$TX_IX \
 	--tx-out $DEST_ADDR+$AMOUNT \
 	--tx-out $SOURCE_ADDR+$CHANGE \
 	--out-file $TX_RAW 

$TX_SIGNED="tx.signed"
# Sign the transaction
cardano-cli transaction sign \
	--tx-body-file $TX_RAW \
	--signing-key-file $SKEY_FILE \
	--testnet-magic $MAGIC_ID  \
	--out-file $TX_SIGNED 

# Submit the transaction
cardano-cli transaction submit \
	--tx-file $TX_SIGNED \
	--testnet-magic $MAGIC_ID

# Check the balances on source address and destination address

# Clean up
rm -f $TX_TMP_DRAFT $PROTOCOL_FILE $TX_RAW $TX_SIGNED
