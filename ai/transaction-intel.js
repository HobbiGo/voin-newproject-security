'use strict';

class TransactionIntelligence {
  analyzeTransaction(txData) {
    const amount = BigInt(txData.amount);
    const fee = BigInt(txData.fee);

    if (amount > 10000n) {
      return {
        status: "WARNING",
        message: "Transaksi bernilai sangat besar (> 10.000 VOIN). Diperlukan verifikasi PIN tambahan."
      };
    }

    if (fee > amount / 10n) {
      return {
        status: "WARNING",
        message: "Biaya (fee) melebihi 10% dari jumlah transfer. Harap periksa kembali."
      };
    }

    return {
      status: "SAFE",
      message: "Struktur biaya dan jumlah transaksi terlihat wajar."
    };
  }
}

module.exports = TransactionIntelligence;
