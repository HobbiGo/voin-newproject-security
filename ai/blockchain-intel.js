'use strict';

class BlockchainIntelligence {
  constructor(nodeInstance) {
    this.node = nodeInstance;
  }

  analyzeWallet(publicKey) {
    const state = this.node.getAccountState(publicKey);
    if (!state) {
      return { found: false, message: "Dompet tidak terdaftar di jaringan VOIN." };
    }
    
    return {
      found: true,
      saldo: state.balance.toString() + " VOIN",
      nonce: state.nonce.toString(),
      status: state.balance > 1000n ? "Whale / High Net Worth" : "Retail / Normal",
      rekomendasi: state.nonce === 0n ? "Dompet baru, waspada transaksi pertama." : "Dompet aktif."
    };
  }

  getNetworkInfo() {
    return {
      chainId: this.node.chainId,
      status: "Aktif",
      totalFeesCollected: this.node.getCollectedFees().toString() + " VOIN"
    };
  }
}

module.exports = BlockchainIntelligence;
