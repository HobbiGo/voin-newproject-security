'use strict';

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const VoinNode = require('./voin-node');
const VoinWallet = require('./wallet');
const VOINAssistant = require('./ai/assistant');
const { initDB } = require('./database');

const app = express();
app.use(cors({ origin: '*' })); 
app.use(express.json());
app.use(express.static('./')); 

const node = new VoinNode('voin-mainnet-1');
const JWT_SECRET = "kunci_rahasia_voin_super_aman_123";

const demoPrivKey = crypto.createHash('sha256').update('rahasia_voin_super_aman').digest('hex');
const serverWallet = new VoinWallet(demoPrivKey);
serverWallet.setupSecurity('pin', 'securePin999'); 
const userWallet = serverWallet.publicKey; 

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ success: false, message: "Akses Ditolak: Belum Login." });

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ success: false, message: "Sesi Kadaluarsa." });
    req.user = user;
    next();
  });
}

app.listen(3000, async () => {
  console.log(`🚀 VOIN WEB4 DASHBOARD & API berjalan di http://localhost:3000`);
  
  await initDB();
  
  const existingAccount = await node.getAccountState(userWallet);
  if (!existingAccount) {
    await node.setAccountState(userWallet, '1500', '5');
    console.log('✅ Akun simulasi didaftarkan (Saldo: 1500).');
  }

  const ai = new VOINAssistant(node);

  app.post('/api/login', (req, res) => {
    const { pin } = req.body;
    if (pin !== 'securePin999') {
      return res.status(401).json({ success: false, message: "PIN Salah!" });
    }
    const token = jwt.sign({ wallet: userWallet }, JWT_SECRET, { expiresIn: '1h' });
    res.json({ success: true, token: token });
  });

  app.post('/api/chat', async (req, res) => {
    try {
      const aiResponse = await ai.chat(req.body.message, userWallet);
      res.json({ reply: aiResponse });
    } catch (error) {
      res.status(500).json({ reply: "[Error]: Sistem AI gagal memproses." });
    }
  });

  app.get('/api/balance', authenticateToken, async (req, res) => {
    try {
      const account = await node.getAccountState(userWallet);
      if (account) {
        res.json({ success: true, balance: account.balance.toString(), nonce: account.nonce.toString(), publicKey: userWallet });
      } else {
        res.json({ success: false, message: "Akun tidak ditemukan" });
      }
    } catch (error) {
      res.status(500).json({ success: false, message: "Gagal mengambil data" });
    }
  });

  app.post('/api/transfer', authenticateToken, async (req, res) => {
    try {
      const { recipient, amount, fee, nonce } = req.body;
      const txData = {
        chainId: 'voin-mainnet-1',
        sender: userWallet,
        recipient: recipient,
        amount: amount.toString(),
        fee: fee.toString(),
        nonce: nonce.toString()
      };

      const signedTx = serverWallet.signTransaction(txData, 'securePin999');
      await node.verifyAndProcessTransaction(signedTx);

      res.json({ success: true, message: "Transaksi Berhasil!" });
    } catch (error) {
      res.status(400).json({ success: false, message: error.message });
    }
  });
});