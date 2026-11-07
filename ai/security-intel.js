'use strict';

class SecurityIntelligence {
  constructor(nodeInstance) {
    this.node = nodeInstance;
  }

  checkAnomaly(txData) {
    const state = this.node.getAccountState(txData.sender);
    if (!state) return { isSuspicious: false, reason: "Akun pengirim belum terdaftar." };

    const nonce = BigInt(txData.nonce);
    const expectedNonce = state.nonce + 1n;

    // Deteksi jika nonce melompat terlalu jauh (indikasi bot)
    if (nonce > expectedNonce + 5n) {
      return {
        isSuspicious: true,
        reason: `Nonce melompat jauh (Diterima: ${nonce}, Diharapkan: ${expectedNonce}). Potensi bot / replay attack.`
      };
    }

    return { isSuspicious: false, reason: "Tidak ada anomali keamanan yang terdeteksi." };
  }
}

module.exports = SecurityIntelligence;
