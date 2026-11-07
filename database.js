'use strict';
const initSqlJs = require('sql.js');
const fs = require('fs');

let db = null;
let SQL = null;

async function initDB() {
  if (db) return;
  SQL = await initSqlJs();
  
  if (fs.existsSync('./voin.db')) {
    const filebuffer = fs.readFileSync('./voin.db');
    db = new SQL.Database(filebuffer);
  } else {
    db = new SQL.Database();
  }

  db.run(`CREATE TABLE IF NOT EXISTS accounts (publicKey TEXT PRIMARY KEY, balance TEXT NOT NULL, nonce TEXT NOT NULL);`);
  saveToFile();
}

function saveToFile() {
  const data = db.export();
  const buffer = Buffer.from(data);
  fs.writeFileSync('./voin.db', buffer);
}

function getRow(query, params) {
  const stmt = db.prepare(query);
  stmt.bind(params);
  if (stmt.step()) {
    const row = stmt.getAsObject();
    stmt.free();
    return row;
  }
  stmt.free();
  return null;
}

module.exports = {
  initDB,
  saveAccount: async (publicKey, balance, nonce) => {
    await initDB();
    const query = `
      INSERT INTO accounts (publicKey, balance, nonce) 
      VALUES (?, ?, ?) 
      ON CONFLICT(publicKey) DO UPDATE SET balance=excluded.balance, nonce=excluded.nonce
    `;
    db.run(query, [publicKey, balance.toString(), nonce.toString()]);
    saveToFile();
    return true;
  },
  getAccount: async (publicKey) => {
    await initDB();
    const row = getRow(`SELECT * FROM accounts WHERE publicKey = ?`, [publicKey]);
    if (!row) return undefined;
    return { balance: BigInt(row.balance), nonce: BigInt(row.nonce) };
  }
};
