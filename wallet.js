'use strict';
const { canonicalizeAndHash, sha256, ec } = require('./crypto-utils');

class Wallet {
  #isPinSet;
  #pinHash;

  constructor(privateKeyHex) {
    if (typeof privateKeyHex !== 'string' || !/^[0-9a-fA-F]{64}$/.test(privateKeyHex)) {
      throw new Error('[Wallet] Private key harus 64 karakter hex.');
    }
    this.signingKey = ec.keyFromPrivate(privateKeyHex, 'hex');
    this.publicKey = this.signingKey.getPublic('hex');
    this.#isPinSet = false;
    this.#pinHash = null;
  }

  static generate() {
    const kp = ec.genKeyPair();
    return new Wallet(kp.getPrivate('hex').padStart(64, '0'));
  }

  setupSecurity(type, credential) {
    if (typeof credential !== 'string' || credential.length < 6) {
      throw new Error('[Wallet Security] PIN/Password minimal 6 karakter.');
    }
    this.#pinHash = sha256(credential);
    this.#isPinSet = true;
  }

  #verifyCredential(credential) {
    if (!this.#isPinSet) throw new Error('[Wallet Security] PIN belum disetup.');
    if (!credential) throw new Error('[Wallet Security] PIN wajib diisi.');
    if (sha256(credential) !== this.#pinHash) {
      throw new Error('[Wallet Security] Verifikasi gagal: PIN salah!');
    }
  }

  signTransaction(txData, pin) {
    this.#verifyCredential(pin);
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