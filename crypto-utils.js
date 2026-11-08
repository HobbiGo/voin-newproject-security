'use strict';
const crypto = require('crypto');
const { ec: EC } = require('elliptic');

const ec = new EC('secp256k1');

function sha256(str) {
  return crypto.createHash('sha256').update(str, 'utf8').digest('hex');
}

function canonicalizeAndHash(txData) {
  if (!txData || typeof txData !== 'object' || Array.isArray(txData)) {
    throw new Error('[Crypto] txData harus berupa objek non-array.');
  }
  const sortedKeys = Object.keys(txData).sort();
  const canonicalObj = {};
  for (const k of sortedKeys) canonicalObj[k] = txData[k];
  const canonicalString = JSON.stringify(canonicalObj);
  const txHash = crypto.createHash('sha256').update(canonicalString, 'utf8').digest();
  return { txHash, canonicalString };
}

module.exports = { canonicalizeAndHash, sha256, ec };