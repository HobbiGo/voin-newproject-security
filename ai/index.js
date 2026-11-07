'use strict';

// Mengambil VOIN CORE dari folder utama (keluar dari folder ai)
const VoinNode = require('../voin-node');
const VOINAssistant = require('./assistant');

async function startAIEngine() {
  console.log("=========================================");
  console.log("   MEMULAI VOIN AI ENGINE V1.0           ");
  console.log("=========================================\n");

  // 1. Nyalakan VOIN CORE
  const node = new VoinNode('voin-mainnet-1');
  
  // Simulasi: Anggap kita punya user dengan dompet ini
  const userWallet = "04" + "a".repeat(128); 
  // Daftarkan user dengan saldo 1500 dan nonce 5
  node.setAccountState(userWallet, '1500', '5'); 

  // 2. Inisialisasi VOIN AI ENGINE
  const ai = new VOINAssistant(node);

  // 3. Simulasi Interaksi
  console.log("[User]: Halo AI, cek saldo dompet saya dong.");
  console.log(await ai.chat("Halo AI, cek saldo dompet saya dong.", userWallet));
  console.log("--------------------------------------------------\n");

  console.log("[User]: Jaringan apa yang sedang aktif?");
  console.log(await ai.chat("Jaringan apa yang sedang aktif?", userWallet));
  console.log("--------------------------------------------------\n");

  console.log("[User]: Apakah sistem kita aman dari hacker?");
  console.log(await ai.chat("Apakah sistem kita aman dari hacker?", userWallet));
  console.log("--------------------------------------------------\n");
}

startAIEngine().catch(console.error);
