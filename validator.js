'use strict';
const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');

const MAX_DIGITS = 30;
const MAX_PAYLOAD_BYTES = 4096;
const ALLOWED_FIELDS = Object.freeze(['chainId', 'sender', 'recipient', 'amount', 'fee', 'nonce']);

const RE_HEX_PUBKEY = /^[0-9a-fA-F]{66,130}$/;
const RE_VOIN_ADDR  = /^voin1[a-z0-9]{38,90}$/;
const RE_HEX_64     = /^[0-9a-fA-F]{64}$/;
const RE_PURE_DIGIT = /^[1-9]\d*$/;
const RE_CHAIN_ID   = /^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$/;

function validateTransactionStructure(txPayload) {
  if (!txPayload || typeof txPayload !== 'object' || Array.isArray(txPayload)) {
    throw new Error('[Validator Reject] Payload transaksi harus berupa objek.');
  }
  const serialized = JSON.stringify(txPayload);
  if (Buffer.byteLength(serialized, 'utf8') > MAX_PAYLOAD_BYTES) {
    throw new Error('[Validator Reject] Payload melebihi batas ukuran maksimum.');
  }
  for (const key of Object.keys(txPayload)) {
    if (!ALLOWED_FIELDS.includes(key)) throw new Error(`[Validator Reject] Field tidak dikenal: '${key}'`);
  }
  for (const f of ALLOWED_FIELDS) {
    if (!(f in txPayload)) throw new Error(`[Validator Reject] Field wajib hilang: '${f}'`);
  }
  const { chainId, sender, recipient, amount, fee, nonce } = txPayload;
  
  if (typeof chainId !== 'string' || !RE_CHAIN_ID.test(chainId)) throw new Error('[Validator Reject] Chain ID tidak valid.');
  if (typeof sender !== 'string' || !RE_HEX_PUBKEY.test(sender)) throw new Error('[Validator Reject] Format Public Key Sender tidak valid.');
  if (typeof recipient !== 'string') throw new Error('[Validator Reject] Recipient harus string.');
  if (!(RE_HEX_PUBKEY.test(recipient) || RE_VOIN_ADDR.test(recipient))) throw new Error('[Validator Reject] Format Recipient tidak valid.');

  const numericFields = { amount, fee, nonce };
  for (const [field, val] of Object.entries(numericFields)) {
    const strVal = String(val);
    if (!RE_PURE_DIGIT.test(strVal)) throw new Error(`[Validator Reject] Field '${field}' harus angka desimal murni.`);
    if (strVal.length > MAX_DIGITS) throw new Error(`[Validator Reject] Field '${field}' melebihi batas digit.`);
    if ((field === 'amount' || field === 'fee') && BigInt(strVal) <= 0n) throw new Error(`[Validator Reject] Field '${field}' harus > 0.`);
  }
  if (sender === recipient) throw new Error('[Validator Reject] Sender dan recipient tidak boleh identik.');
  return true;
}

function validateSignatureFormat(signature, publicKey) {
  if (!signature || typeof signature !== 'object' || Array.isArray(signature)) throw new Error('[Validator Reject] Format tanda tangan tidak valid.');
  const { r, s } = signature;
  if (typeof r !== 'string' || !RE_HEX_64.test(r)) throw new Error("[Validator Reject] Komponen signature 'r' harus 64 hex.");
  if (typeof s !== 'string' || !RE_HEX_64.test(s)) throw new Error("[Validator Reject] Komponen signature 's' harus 64 hex.");
  if (/^0+$/.test(r) || /^0+$/.test(s)) throw new Error('[Validator Reject] Komponen signature tidak boleh nol.');
  if (typeof publicKey !== 'string' || !RE_HEX_PUBKEY.test(publicKey)) throw new Error('[Validator Reject] Format Public Key tidak valid.');
  try {
    const key = ec.keyFromPublic(publicKey, 'hex');
    if (!key.validate().result) throw new Error('invalid point');
  } catch { throw new Error('[Validator Reject] Public key gagal divalidasi kurva Secp256k1.'); }
  return true;
}

module.exports = { validateTransactionStructure, validateSignatureFormat };
