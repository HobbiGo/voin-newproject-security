'use strict';
const BlockchainIntelligence = require('./blockchain-intel');
const TransactionIntelligence = require('./transaction-intel');
const SecurityIntelligence = require('./security-intel');

class VOINAssistant {
  constructor(nodeInstance) {
    this.node = nodeInstance;
    this.blockchainIntel = new BlockchainIntelligence(nodeInstance);
    this.transactionIntel = new TransactionIntelligence();
    this.securityIntel = new SecurityIntelligence(nodeInstance);
  }

  async chat(userPrompt, walletPublicKey) {
    const lowerPrompt = userPrompt.toLowerCase();

    // 1. Intent: Cek Saldo / Profil Dompet
    if (lowerPrompt.includes("saldo") || lowerPrompt.includes("dompet") || lowerPrompt.includes("wallet")) {
      const report = this.blockchainIntel.analyzeWallet(walletPublicKey);
      if (!report.found) return `[AI]: ${report.message}`;
      return `[AI]: Saldo Anda saat ini adalah ${report.saldo} (Nonce: ${report.nonce}). Status: ${report.status}. ${report.rekomendasi}`;
    }

    // 2. Intent: Cek Status Jaringan
    if (lowerPrompt.includes("jaringan") || lowerPrompt.includes("network") || lowerPrompt.includes("chain")) {
      const info = this.blockchainIntel.getNetworkInfo();
      return `[AI]: Saat ini kita berada di jaringan ${info.chainId}. Status: ${info.status}. Total fee terkumpul: ${info.totalFeesCollected}.`;
    }

    // 3. Intent: Cek Keamanan
    if (lowerPrompt.includes("keamanan") || lowerPrompt.includes("security") || lowerPrompt.includes("hacker")) {
      return `[AI]: Sistem keamanan VOIN CORE aktif. Validasi tanda tangan digital, anti-spoofing, dan proteksi nonce berjalan normal.`;
    }

    // 4. Fallback
    return `[AI]: Maaf, saya tidak mengerti maksud Anda. Anda bisa bertanya tentang "saldo", "jaringan", atau "keamanan".`;
  }
}

module.exports = VOINAssistant;
