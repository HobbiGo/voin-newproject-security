'use strict';
const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const { canonicalizeAndHash } = require('./crypto-utils');
const { validateTransactionStructure, validateSignatureFormat } = require('./validator');

class VoinNode {
  #stateDB = new Map();
  #totalFeesCollected = 0n;

  constructor(chainId = 'voin-mainnet-1') {
    if (typeof chainId !== 'string' || !chainId.trim()) throw new Error('[Node Init] chainId tidak valid.');
    this.chainId = chainId;
  }

  setAccountState(publicKey, balance, nonce) {
    this.#stateDB.set(publicKey, { balance: BigInt(balance), nonce: BigInt(nonce) });
  }

  getAccountState(publicKey) {
    const s = this.#stateDB.get(publicKey);
    return s ? { balance: s.balance, nonce: s.nonce } : undefined;
  }

  getCollectedFees() { return this.#totalFeesCollected; }

  verifyAndProcessTransaction(signedTransaction) {
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
    
    if (!this.#stateDB.has(publicKey)) throw new Error('[Node Reject] Akun pengirim tidak terdaftar.');
    const account = this.#stateDB.get(publicKey);

    const key = ec.keyFromPublic(publicKey, 'hex');
    const { txHash } = canonicalizeAndHash(txData);
    let valid = false;
    try { valid = key.verify(txHash, signature); }
    catch { throw new Error('[Node Reject] Proses verifikasi kriptografi gagal.'); }
    if (!valid) throw new Error('[Node Reject] Tanda tangan kriptografi tidak sah!');

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

    // Mutasi State
    account.balance -= totalCost;
    account.nonce += 1n;
    this.#totalFeesCollected += fee;

    if (!this.#stateDB.has(txData.recipient)) this.#stateDB.set(txData.recipient, { balance: 0n, nonce: 0n });
    this.#stateDB.get(txData.recipient).balance += amount;

    return true;
  }
}

module.exports = VoinNode;
