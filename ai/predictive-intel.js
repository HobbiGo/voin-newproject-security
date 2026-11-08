'use strict';

class PredictiveIntelligence {
  predictBalance(balance, amount, fee) {
    const bal = BigInt(balance);
    const amt = BigInt(amount);
    const f = BigInt(fee);
    
    const afterBalance = bal - (amt + f);
    const burnRate = amt > 0n ? (amt * 100n) / bal : 0n; // Persentase saldo yang dihabiskan

    let prediction = `Setelah transaksi ini, saldo Anda akan menjadi ${afterBalance} VOIN. `;
    
    if (burnRate > 50n) {
      prediction += "Anda menghabiskan lebih dari 50% saldo Anda dalam satu transaksi.";
    } else {
      prediction += "Kondisi dompet Anda masih sangat sehat.";
    }

    return prediction;
  }
}

module.exports = PredictiveIntelligence;
