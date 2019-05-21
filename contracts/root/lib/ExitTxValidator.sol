pragma solidity ^0.5.2;

import { BytesLib } from "../../common/lib/BytesLib.sol";
import { Common } from "../../common/lib/Common.sol";
import { RLPEncode } from "../../common/lib/RLPEncode.sol";
import { RLPReader } from "solidity-rlp/contracts/RLPReader.sol";

library ExitTxValidator {
  using RLPReader for bytes;
  using RLPReader for RLPReader.RLPItem;
  bytes constant public networkId = "\x0d";

  // 0x2e1a7d4d = keccak256('withdraw(uint256)').slice(0, 4)
  bytes4 constant WITHDRAW_FUNC_SIG = 0x2e1a7d4d;
  // 0xa9059cbb = keccak256('transfer(address,uint256)').slice(0, 4)
  bytes4 constant TRANSFER_FUNC_SIG = 0xa9059cbb;

  /**
   * @notice Process the transaction to start a MoreVP style exit from
   * @param exitTx Signed exit transaction
   * exitor Need I say more?
   */
  function processExitTx(bytes memory exitTx)
    public
    view
    returns(uint256 exitAmountOrTokenId, address childToken, address participant, bool burnt)
  {
    RLPReader.RLPItem[] memory txList = exitTx.toRlpItem().toList();
    require(txList.length == 9, "MALFORMED_WITHDRAW_TX");
    childToken = RLPReader.toAddress(txList[3]); // corresponds to "to" field in tx
    participant = getAddressFromTx(txList);
    if (participant == msg.sender) { // exit tx is signed by exitor himself
      (exitAmountOrTokenId, burnt) = processExitTxSender(RLPReader.toBytes(txList[5]));
    } else {
      exitAmountOrTokenId = processExitTxCounterparty(RLPReader.toBytes(txList[5]));
    }
  }

  function processExitTxSender(bytes memory txData)
    internal
    view
    returns (uint256 exitAmountOrTokenId, bool burnt)
  {
    bytes4 funcSig = BytesLib.toBytes4(BytesLib.slice(txData, 0, 4));
    if (funcSig == WITHDRAW_FUNC_SIG) {
      require(txData.length == 36, "Invalid tx"); // 4 bytes for funcSig and a single bytes32 parameter
      exitAmountOrTokenId = BytesLib.toUint(txData, 4);
      burnt = true;
    } else if (funcSig == TRANSFER_FUNC_SIG) {
      require(txData.length == 68, "Invalid tx"); // 4 bytes for funcSig and a 2 bytes32 parameters (to, value)
      exitAmountOrTokenId = BytesLib.toUint(txData, 4);
    } else {
      revert("Exit tx type not supported");
    }
  }

  function processExitTxCounterparty(bytes memory txData)
    internal
    view
    returns (uint256 exitAmountOrTokenId)
  {
    require(txData.length == 68, "Invalid tx"); // 4 bytes for funcSig and a 2 bytes32 parameters (to, value)
    bytes4 funcSig = BytesLib.toBytes4(BytesLib.slice(txData, 0, 4));
    require(funcSig == TRANSFER_FUNC_SIG, "Only supports exiting from transfer txs");
    require(
      msg.sender == address(BytesLib.toUint(txData, 4)), // to
      "Exit tx doesnt concern the exitor"
    );
    exitAmountOrTokenId = BytesLib.toUint(txData, 36); // value
  }

  /**
   * @notice Process the transaction signed by the counterparty to start a MoreVP style exit from
   * @param exitTx Signed exit transaction
   * @param counterparty Need I say more?
   */
  function processExitTxCounterparty(bytes memory exitTx, address counterparty)
    public
    view
    returns(uint256 exitAmountOrTokenId, address childToken)
  {
    RLPReader.RLPItem[] memory txList = exitTx.toRlpItem().toList();
    require(txList.length == 9, "MALFORMED_WITHDRAW_TX");
    require(counterparty == getAddressFromTx(txList), "TRANSACTION_SENDER_MISMATCH");
    childToken = RLPReader.toAddress(txList[3]); // corresponds to "to" field in tx
    bytes memory txData = RLPReader.toBytes(txList[5]);

  }

  function getAddressFromTx(RLPReader.RLPItem[] memory txList)
    internal
    view
    returns (address)
  {
    bytes[] memory rawTx = new bytes[](9);
    for (uint8 i = 0; i <= 5; i++) {
      rawTx[i] = txList[i].toBytes();
    }
    rawTx[4] = hex"";
    rawTx[6] = networkId;
    rawTx[7] = hex"";
    rawTx[8] = hex"";

    return ecrecover(
      keccak256(RLPEncode.encodeList(rawTx)),
      Common.getV(txList[6].toBytes(), Common.toUint8(networkId)),
      bytes32(txList[7].toUint()),
      bytes32(txList[8].toUint())
    );
  }
}
