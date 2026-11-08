'use strict';
const { ec, canonicalizeAndHash } = require('./crypto-utils');
const { validateTransactionStructure, validateSignatureFormat } = require('./validator');
const db = require('./database');

class VoinNode {
  #totalFeesCollected = 0n;

  constructor(chainId = 'voin-mainnet-1') {
    if (typeof chainId !== 'string' || !chainId.trim()) throw new Error('[Node Init] chainId tidak valid.');
    this.chainId = chainId;
  }

  async setAccountState(publicKey, balance, nonce) {
    await db.saveAccount(publicKey, balance, nonce);
  }

  async getAccountState(publicKey) {
    return await db.getAccount(publicKey);
  }

  getCollectedFees() { return this.#totalFeesCollected; }

  async verifyAndProcessTransaction(signedTransaction) {
    if (!signedTransaction || typeof signedTransaction !== 'object' || Array.isArray(signedTransaction)) {
      throw new Error('[Node Reject] Paket transaksi kosong atau tidak valid.');
    }
    const { txData, publicKey, signature } = signedTransaction;

    try {
      validateTransactionStructure(txData);
      validateSignatureFormat(signature, publicKey);
    } catch (err) { throw new Error(`[Node Reject] ${err.message}`); }

    if (txData.chainId !== this.chainId) throw new Error('[Node Reject] Chain ID tidak cocok!');
    if (txData.sender !== publicKey) throw new Error('[Node Reject] Spoofing terdeteksi!');
    
    const account = await db.getAccount(publicKey);
    if (!account) throw new Error('[Node Reject] Akun pengirim tidak terdaftar.');

    // Verifikasi Kriptografi
    const key = ec.keyFromPublic(publicKey, 'hex');
    const { txHash } = canonicalizeAndHash(txData);
    let valid = false;
    try { valid = key.verify(txHash, signature); }
    catch { throw new Error('[Node Reject] Proses verifikasi kriptografi gagal.'); }
    if (!valid) throw new Error('[Node Reject] Tanda tangan kriptografi tidak sah!');

    // Cek Nonce & Saldo
    const amount = BigInt(txData.amount);
    const fee    = BigInt(txData.fee);
    const nonce  = BigInt(txData.nonce);

    if (nonce !== account.nonce + 1n) {
      throw new Error(`[Node Reject] Nonce tidak valid! Diterima: ${nonce}, Diharapkan: ${account.nonce + 1n}`);
    }

    const totalCost = amount + fee;
    if (account.balance < totalCost) {
      throw new Error(`[Node Reject] Saldo tidak cukup. Saldo: ${account.balance}, Dibutuhkan: ${totalCost}`);
    }

    // Update Database
    await db.saveAccount(publicKey, account.balance - totalCost, account.nonce + 1n);
    this.#totalFeesCollected += fee;

    let recipientAccount = await db.getAccount(txData.recipient);
    if (!recipientAccount) recipientAccount = { balance: 0n, nonce: 0n };
    await db.saveAccount(txData.recipient, recipientAccount.balance + amount, recipientAccount.nonce);

    return true;
  }
}

module.exports = VoinNode;