'use strict';
const sqlite3 = require('sqlite3').verbose();

// Membuat/membuka file database
const db = new sqlite3.Database('./voin.db');

// Inisialisasi Tabel (hanya dibuat jika belum ada)
db.serialize(() => {
  db.run(`
    CREATE TABLE IF NOT EXISTS accounts (
      publicKey TEXT PRIMARY KEY,
      balance TEXT NOT NULL,
      nonce TEXT NOT NULL
    )
  `);
});

module.exports = {
  // Simpan atau Update state akun
  saveAccount: (publicKey, balance, nonce) => {
    return new Promise((resolve, reject) => {
      const query = `
        INSERT INTO accounts (publicKey, balance, nonce) 
        VALUES (?, ?, ?) 
        ON CONFLICT(publicKey) DO UPDATE SET balance=excluded.balance, nonce=excluded.nonce
      `;
      db.run(query, [publicKey, balance.toString(), nonce.toString()], function(err) {
        if (err) reject(err);
        else resolve(true);
      });
    });
  },

  // Ambil state akun
  getAccount: (publicKey) => {
    return new Promise((resolve, reject) => {
      db.get(`SELECT * FROM accounts WHERE publicKey = ?`, [publicKey], (err, row) => {
        if (err) reject(err);
        else if (!row) resolve(undefined);
        else resolve({ balance: BigInt(row.balance), nonce: BigInt(row.nonce) });
      });
    });
  }
};
