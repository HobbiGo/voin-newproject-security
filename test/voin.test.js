'use strict';

const { expect } = require('chai');
const { ec: EC } = require('elliptic');
const ec = new EC('secp256k1');

// Mengarah ke file yang ada di luar folder test/ (sesuaikan dengan struktur folder)
const VoinNode = require('../voin-node');
const Wallet = require('../wallet');
const {
  validateTransactionStructure,
  validateSignatureFormat,
} = require('../validator');

// Helper: Buat wallet acak baru
function makeWallet() {
  return Wallet.generate();
}

// Helper: Buat template transaksi dasar
function baseTx(overrides = {}) {
  return {
    chainId: 'voin-mainnet-1',
    sender: null, // Akan diisi di dalam test
    recipient: ec.genKeyPair().getPublic('hex'),
    amount: '100',
    fee: '1',
    nonce: '1',
    ...overrides,
  };
}

describe('Validator', () => {
  it('menerima payload valid', () => {
    const w = makeWallet();
    const tx = baseTx({ sender: w.publicKey });
    expect(validateTransactionStructure(tx)).to.equal(true);
  });

  it('menolak field ekstra', () => {
    const w = makeWallet();
    const tx = baseTx({ sender: w.publicKey, evil: 'x' });
    expect(() => validateTransactionStructure(tx)).to.throw(/Field tidak dikenal/);
  });

  it('menolak field hilang', () => {
    const tx = { chainId: 'voin-mainnet-1' };
    expect(() => validateTransactionStructure(tx)).to.throw(/Field wajib hilang/);
  });

  it('menolak chainId tidak valid', () => {
    const w = makeWallet();
    const tx = baseTx({ sender: w.publicKey, chainId: 'UPPER!' });
    expect(() => validateTransactionStructure(tx)).to.throw(/Chain ID/);
  });

  it('menolak amount negatif / float', () => {
    const w = makeWallet();
    for (const bad of ['-1', '1.5', '01', '0', '1e3']) {
      const tx = baseTx({ sender: w.publicKey, amount: bad });
      expect(() => validateTransactionStructure(tx), `amount=${bad}`).to.throw();
    }
  });

  it('menolak sender = recipient', () => {
    const w = makeWallet();
    const tx = baseTx({ sender: w.publicKey, recipient: w.publicKey });
    expect(() => validateTransactionStructure(tx)).to.throw(/identik/);
  });

  it('menolak signature r/s bukan 64 hex', () => {
    const w = makeWallet();
    expect(() =>
      validateSignatureFormat({ r: 'abc', s: 'a'.repeat(64) }, w.publicKey)
    ).to.throw(/r' harus tepat 64/);
  });

  it('menolak signature r/s nol', () => {
    const w = makeWallet();
    expect(() =>
      validateSignatureFormat({ r: '0'.repeat(64), s: '0'.repeat(64) }, w.publicKey)
    ).to.throw(/tidak boleh nol/);
  });

  it('menolak public key bukan titik kurva', () => {
    const fake = '11'.repeat(33); // Format valid, tapi bukan titik kurva
    expect(() =>
      validateSignatureFormat({ r: '1'.repeat(64), s: '1'.repeat(64) }, fake)
    ).to.throw(/gagal divalidasi/);
  });
});

describe('VoinNode', () => {
  let node, sender, recipient;

  beforeEach(() => {
    node = new VoinNode('voin-mainnet-1');
    sender = makeWallet();
    recipient = makeWallet();
    node.setAccountState(sender.publicKey, '1000', '0');
  });

  function makeSigned(txData) {
    // Versi Node.js tidak async, jadi langsung return
    return sender.signTransaction(txData); 
  }

  function validTx(overrides = {}) {
    return baseTx({
      sender: sender.publicKey,
      recipient: recipient.publicKey,
      nonce: '1',
      ...overrides,
    });
  }

  it('memproses transaksi valid', () => {
    const signed = makeSigned(validTx());
    expect(node.verifyAndProcessTransaction(signed)).to.equal(true);
    
    const s = node.getAccountState(sender.publicKey);
    expect(s.balance).to.equal(899n); // 1000 - 100 - 1
    expect(s.nonce).to.equal(1n);
    expect(node.getAccountState(recipient.publicKey).balance).to.equal(100n);
    expect(node.getCollectedFees()).to.equal(1n);
  });

  it('menolak chainId beda', () => {
    const signed = makeSigned(validTx({ chainId: 'voin-testnet-9' }));
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw(/Chain ID/);
  });

  it('menolak spoofing sender', () => {
    const other = makeWallet();
    const signed = makeSigned(validTx({ sender: other.publicKey }));
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw(/Spoofing/);
  });

  it('menolak nonce replay', () => {
    const signed = makeSigned(validTx({ nonce: '1' }));
    node.verifyAndProcessTransaction(signed);
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw(/Nonce/);
  });

  it('menolak saldo tidak cukup', () => {
    const signed = makeSigned(validTx({ amount: '5000' }));
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw(/Saldo tidak cukup/);
  });

  it('menolak tanda tangan palsu', () => {
    const signed = makeSigned(validTx());
    signed.txData.amount = '9999'; // Mengubah data setelah ditandatangani
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw(/tidak sah/);
  });

  it('menolak payload terlalu besar', () => {
    const signed = makeSigned(validTx());
    signed.txData.chainId = 'a'.repeat(5000);
    expect(() => node.verifyAndProcessTransaction(signed)).to.throw();
  });
});
