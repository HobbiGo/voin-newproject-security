'use strict';

const express = require('express');
const cors = require('cors');
const VoinNode = require('./voin-node');
const VOINAssistant = require('./ai/assistant');

const app = express();
app.use(cors());
app.use(express.json());

// Nyalakan VOIN CORE
const node = new VoinNode('voin-mainnet-1');
const userWallet = "04" + "a".repeat(128); 
node.setAccountState(userWallet, '1500', '5'); 

// Nyalakan AI Engine
const ai = new VOINAssistant(node);

// Endpoint API
app.post('/api/chat', async (req, res) => {
  try {
    const userPrompt = req.body.message;
    const aiResponse = await ai.chat(userPrompt, userWallet);
    res.json({ reply: aiResponse });
  } catch (error) {
    res.status(500).json({ reply: "[Error]: Sistem AI gagal memproses." });
  }
});

// Jalankan Server
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🚀 VOIN AI API Server berjalan di http://localhost:${PORT}`);
});
