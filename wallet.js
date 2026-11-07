'use strict';
const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const { canonicalizeAndHash } = require('./crypto-utils');

class Wallet {
  constructor(privateKeyHex) {
    if (typeof privateKeyHex !== 'string' || !/^[0-9a-fA-F]{64}$/.test(privateKeyHex)) {
      throw new Error('[Wallet] Private key harus 64 karakter hex.');
    }
    this.signingKey = ec.keyFromPrivate(privateKeyHex, 'hex');
    this.publicKey = this.signingKey.getPublic('hex');
  }
  static generate() {
    const kp = ec.genKeyPair();
    return new Wallet(kp.getPrivate('hex').padStart(64, '0'));
  }
  signTransaction(txData) {
    const { txHash } = canonicalizeAndHash(txData);
    const sig = this.signingKey.sign(txHash, { canonical: true });
    return {
      txData,
      publicKey: this.publicKey,
      signature: {
        r: sig.r.toString(16).padStart(64, '0'),
        s: sig.s.toString(16).padStart(64, '0'),
      },
    };
  }
}
module.exports = Wallet;
