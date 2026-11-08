'use strict';

class PaymentIntelligence {
  analyzePayment(amount, fee, balance) {
    const amt = BigInt(amount);
    const f = BigInt(fee);
    const bal = BigInt(balance);
    
    const totalCost = amt + f;
    const remainingBalance = bal - totalCost;

    let warning = null;
    if (f > amt / 10n) {
      warning = "Biaya (fee) melebihi 10% dari nominal transfer. Ini tidak efisien.";
    } else if (remainingBalance < 50n) {
      warning = "Peringatan: Saldo Anda akan tersisa sangat sedikit (< 50 VOIN) setelah transaksi ini.";
    } else if (amt > 1000n) {
      warning = "Transaksi bernilai besar terdeteksi. Pastikan alamat penerima benar.";
    }

    return {
      isSafe: !warning,
      warning: warning,
      recommendation: warning ? "Tunda transaksi atau periksa kembali detail." : "Transaksi aman dan wajar."
    };
  }
}

module.exports = PaymentIntelligence;
