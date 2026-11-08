'use strict';
const BlockchainIntelligence = require('./blockchain-intel');
const TransactionIntelligence = require('./transaction-intel');
const SecurityIntelligence = require('./security-intel');
const PaymentIntelligence = require('./payment-intel');
const PredictiveIntelligence = require('./predictive-intel');

class VOINAssistant {
  constructor(nodeInstance) {
    this.node = nodeInstance;
    this.blockchainIntel = new BlockchainIntelligence(nodeInstance);
    this.transactionIntel = new TransactionIntelligence();
    this.securityIntel = new SecurityIntelligence(nodeInstance);
    this.paymentIntel = new PaymentIntelligence();
    this.predictiveIntel = new PredictiveIntelligence();
  }

  async chat(userPrompt, walletPublicKey) {
    const lowerPrompt = userPrompt.toLowerCase();

    // 1. Cek Saldo
    if (lowerPrompt.includes("saldo") || lowerPrompt.includes("dompet")) {
      const report = this.blockchainIntel.analyzeWallet(walletPublicKey);
      if (!report.found) return `[AI]: ${report.message}`;
      return `[AI]: Saldo Anda: ${report.saldo} (Nonce: ${report.nonce}). Status: ${report.status}.`;
    }

    // 2. Opsi 1 & 3: Analisis Transaksi & Prediksi (Jika user menyebut angka)
    if (lowerPrompt.includes("kirim") || lowerPrompt.includes("transfer") || lowerPrompt.includes("aman")) {
      // Ekstrak angka dari teks user (misal: "kirim 100 voin")
      const match = userPrompt.match(/\d+/);
      const amount = match ? match[0] : "100"; // Default 100 jika tidak ada angka
      
      const account = await this.node.getAccountState(walletPublicKey);
      if (!account) return `[AI]: Akun Anda tidak ditemukan di database.`;

      const fee = "1";
      
      // Analisis Pembayaran
      const payAnalysis = this.paymentIntel.analyzePayment(amount, fee, account.balance);
      // Prediksi Saldo
      const prediction = this.predictiveIntel.predictBalance(account.balance, amount, fee);

      let response = `[AI]: Analisis untuk pengiriman ${amount} VOIN:\n`;
      response += `- Keamanan: ${payAnalysis.recommendation} ${payAnalysis.warning ? '⚠️ ' + payAnalysis.warning : '✅'}\n`;
      response += `- Prediksi: ${prediction}`;

      return response;
    }

    // 3. Cek Keamanan Jaringan
    if (lowerPrompt.includes("keamanan") || lowerPrompt.includes("hacker") || lowerPrompt.includes("jaringan")) {
      return `[AI]: Sistem keamanan VOIN CORE aktif. Validasi tanda tangan digital dan proteksi nonce berjalan normal.`;
    }

    return `[AI]: Saya siap membantu. Anda bisa bertanya "cek saldo" atau "apakah aman kirim 500 VOIN?".`;
  }
}

module.exports = VOINAssistant;
