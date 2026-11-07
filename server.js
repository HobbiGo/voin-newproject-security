'use strict';

const express = require('express');
const cors = require('cors');
const VoinNode = require('./voin-node');
const VOINAssistant = require('./ai/assistant');
const { initDB } = require('./database'); // Import Database

const app = express();
app.use(cors({ origin: '*' })); 
app.use(express.json());

const node = new VoinNode('voin-mainnet-1');
const userWallet = "04" + "a".repeat(128); 

// Nyalakan server
app.listen(3000, async () => {
  console.log(`🚀 VOIN AI API Server berjalan di http://localhost:3000`);
  
  // Inisialisasi Database dulu
  await initDB();
  
  // Cek akun
  const existingAccount = await node.getAccountState(userWallet);
  if (!existingAccount) {
    await node.setAccountState(userWallet, '1500', '5');
    console.log('✅ Akun simulasi berhasil didaftarkan ke Database (Saldo: 1500).');
  } else {
    console.log('✅ Akun simulasi ditemukan di Database (Data tidak hilang).');
  }

  const ai = new VOINAssistant(node);

  app.post('/api/chat', async (req, res) => {
    try {
      const aiResponse = await ai.chat(req.body.message, userWallet);
      res.json({ reply: aiResponse });
    } catch (error) {
      res.status(500).json({ reply: "[Error]: Sistem AI gagal memproses." });
    }
  });
});
