'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const VoinWallet = require('../wallet');
const VoinNode = require('../voin-node');

const TEST_CHAIN_ID = "voin-testnet-alpha";
const VALID_RECIPIENT = "voin1recipient_bob_1234567890123456789012345";

function setupTestEnvironment(initialBalance = 100n, initialNonce = 0n) {
  const node = new VoinNode(TEST_CHAIN_ID);
  const wallet = VoinWallet.generate();
  wallet.setupSecurity('pin', 'securePin999');
  node.setAccountState(wallet.publicKey, initialBalance, initialNonce);
  return { node, wallet };
}

test('Skenario 1: Transaksi Normal Berhasil & Mutasi State Akurat', () => {
  const { node, wallet } = setupTestEnvironment(100n, 0n);
  const tx = {
    chainId: TEST_CHAIN_ID, sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "30", fee: "2", nonce: "1"
  };
  const signedTx = wallet.signTransaction(tx, 'securePin999');
  const success = node.verifyAndProcessTransaction(signedTx);

  assert.equal(success, true, "Transaksi normal harus berhasil");
  const senderState = node.getAccountState(wallet.publicKey);
  const recipientState = node.getAccountState(VALID_RECIPIENT);

  assert.equal(senderState.balance, 68n, "Saldo pengirim harus 68n");
  assert.equal(senderState.nonce, 1n, "Nonce pengirim harus 1");
  assert.equal(recipientState.balance, 30n, "Saldo penerima harus 30n");
});

test('Skenario 2: PIN Salah pada Dompet (Ditolak Sistem)', () => {
  const { node, wallet } = setupTestEnvironment(100n, 0n);
  const tx = {
    chainId: TEST_CHAIN_ID, sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "10", fee: "1", nonce: "1"
  };

  assert.throws(() => {
    wallet.signTransaction(tx, 'salahTotal');
  }, /Verifikasi gagal: PIN salah!/, "Harus melempar error PIN salah");

  const senderState = node.getAccountState(wallet.publicKey);
  assert.equal(senderState.balance, 100n, "Saldo tidak boleh berubah");
  assert.equal(senderState.nonce, 0n, "Nonce tidak boleh berubah");
});

test('Skenario 3: Saldo Kurang (Ditolak Node & State Tidak Berubah)', () => {
  const { node, wallet } = setupTestEnvironment(10n, 0n); 
  const tx = {
    chainId: TEST_CHAIN_ID, sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "50", fee: "2", nonce: "1"
  };
  const signedTx = wallet.signTransaction(tx, 'securePin999');

  assert.throws(() => {
    node.verifyAndProcessTransaction(signedTx);
  }, /Saldo tidak cukup/, "Node harus menolak transaksi kurang saldo");

  const senderState = node.getAccountState(wallet.publicKey);
  assert.equal(senderState.balance, 10n, "Saldo pengirim harus tetap utuh");
  assert.equal(senderState.nonce, 0n, "Nonce pengirim tidak boleh bertambah");
});

test('Skenario 4: Replay Attack - Mengirim Ulang Paket Signed', () => {
  const { node, wallet } = setupTestEnvironment(100n, 0n);
  const tx = {
    chainId: TEST_CHAIN_ID, sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "10", fee: "1", nonce: "1"
  };
  const signedTx = wallet.signTransaction(tx, 'securePin999');
  assert.equal(node.verifyAndProcessTransaction(signedTx), true);

  assert.throws(() => {
    node.verifyAndProcessTransaction(signedTx);
  }, /Nonce tidak valid/, "Node harus menolak replay attack");
});

test('Skenario 5: Chain ID Salah / Lintas Jaringan Berbeda', () => {
  const { node, wallet } = setupTestEnvironment(100n, 0n);
  const tx = {
    chainId: "voin-malicious-chain", sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "10", fee: "1", nonce: "1"
  };
  const signedTx = wallet.signTransaction(tx, 'securePin999');
  
  assert.throws(() => {
    node.verifyAndProcessTransaction(signedTx);
  }, /Chain ID tidak cocok/, "Node harus menolak transaksi dari chain ID lain");
});

test('Skenario 6: Modifikasi Payload Setelah Signing (Tampering)', () => {
  const { node, wallet } = setupTestEnvironment(100n, 0n);
  const tx = {
    chainId: TEST_CHAIN_ID, sender: wallet.publicKey, recipient: VALID_RECIPIENT,
    amount: "10", fee: "1", nonce: "1"
  };
  const signedTx = wallet.signTransaction(tx, 'securePin999');
  
  signedTx.txData.amount = "999"; // Penyerang mengubah amount

  assert.throws(() => {
    node.verifyAndProcessTransaction(signedTx);
  }, /Tanda tangan kriptografi tidak sah/, "Node harus mendeteksi modifikasi data");
});
