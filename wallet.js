'use strict';
const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');
const { canonicalizeAndHash, sha256 } = require('./crypto-utils');

class Wallet {
  constructor(privateKeyHex) {
    if (typeof privateKeyHex !== 'string' || !/^[0-9a-fA-F]{64}$/.test(privateKeyHex)) {
      throw new Error('[Wallet] Private key harus 64 karakter hex.');
    }
    this.signingKey = ec.keyFromPrivate(privateKeyHex, 'hex');
    this.publicKey = this.signingKey.getPublic('hex');
    
    // State untuk keamanan
    this.#isPinSet = false;
    this.#pinHash = null;
  }

  // Private fields (benar-benar privat, tidak bisa diakses dari luar)
  #isPinSet;
  #pinHash;

  static generate() {
    const kp = ec.genKeyPair();
    return new Wallet(kp.getPrivate('hex').padStart(64, '0'));
  }

  /**
   * Mendaftarkan PIN atau Password baru.
   * @param {string} type - 'pin' atau 'password'
   * @param {string} credential - PIN/Password asli
   */
  setupSecurity(type, credential) {
    if (typeof credential !== 'string' || credential.length < 6) {
      throw new Error('[Wallet Security] PIN/Password minimal 6 karakter.');
    }
    // Simpan hash-nya saja, jangan simpan teks aslinya demi keamanan
    this.#pinHash = sha256(credential);
    this.#isPinSet = true;
  }

  /**
   * Memverifikasi PIN sebelum melakukan aksi sensitif.
   */
  #verifyCredential(credential) {
    if (!this.#isPinSet) throw new Error('[Wallet Security] PIN belum disetup.');
    if (!credential) throw new Error('[Wallet Security] PIN/Password wajib diisi.');
    
    const inputHash = sha256(credential);
    if (inputHash !== this.#pinHash) {
      throw new Error('[Wallet Security] Verifikasi gagal: PIN salah!');
    }
  }

  /**
   * Menandatangani transaksi. Wajib menyertakan PIN.
   * @param {object} txData - Data transaksi
   * @param {string} pin - PIN yang dimasukkan pengguna
   */
  signTransaction(txData, pin) {
    // 1. Verifikasi PIN terlebih dahulu
    this.#verifyCredential(pin);

    // 2. Jika PIN benar, lanjutkan tanda tangan
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
