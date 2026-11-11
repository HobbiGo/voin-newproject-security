name: VOIN Solidity Security Tests

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    defaults:
      run:
        shell: bash
        working-directory: solidity-tests

    env:
      FOUNDRY_OPTIMIZER: "true"
      FOUNDRY_OPTIMIZER_RUNS: "200"
      FOUNDRY_VIA_IR: "true"
      FOUNDRY_FUZZ_RUNS: "256"
      BSC_RPC_URL: "https://bsc-rpc.publicnode.com"

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
        with:
          version: stable

      - name: Show tool version
        run: forge --version

      - name: Install OpenZeppelin v5.0.2 contracts only
        run: |
          mkdir -p lib

          git clone \
            --depth 1 \
            --branch v5.0.2 \
            https://github.com/OpenZeppelin/openzeppelin-contracts.git \
            lib/openzeppelin-contracts

          git -C lib/openzeppelin-contracts \
            sparse-checkout init --cone

          git -C lib/openzeppelin-contracts \
            sparse-checkout set contracts

          git -C lib/openzeppelin-contracts rev-parse HEAD

      - name: Configure OpenZeppelin import mapping
        run: |
          touch remappings.txt

          printf '\n@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/\n' \
            >> remappings.txt

      - name: Compile contracts and tests
        run: forge build

      - name: Verify all four test suites are detected
        run: |
          forge test \
            --list \
            --match-contract '^VOINPresaleSecurityTest$' \
            | tee detected-legacy-tests.txt

          grep -q \
            'testExactPaymentRecordsAllocation' \
            detected-legacy-tests.txt

          forge test \
            --list \
            --match-contract '^VOINPresalePaymentsDraftTest$' \
            | tee detected-payment-tests.txt

          grep -q \
            'testBnbExactPaymentAndAllocation' \
            detected-payment-tests.txt

          grep -q \
            'testUsdtExactPaymentAndAllocation' \
            detected-payment-tests.txt

          forge test \
            --list \
            --match-contract '^VOINPresalePaymentsAdversarialTest$' \
            | tee detected-adversarial-tests.txt

          grep -q \
            'testRefundCallbackCannotReenterPurchase' \
            detected-adversarial-tests.txt

          grep -q \
            'testFuzzUsdtDebitAndAllocationConservation' \
            detected-adversarial-tests.txt

          forge test \
            --list \
            --match-contract '^VOINPresalePaymentsForkTest$' \
            | tee detected-fork-tests.txt

          grep -q \
            'testForkQuotesMatchRealFeedAnswers' \
            detected-fork-tests.txt

          grep -q \
            'testForkRealUsdtCodeApprovalPurchaseAndWithdrawal' \
            detected-fork-tests.txt

      - name: Run existing isolated EVM tests
        run: |
          forge test \
            --match-contract '^VOINPresaleSecurityTest$' \
            -vvv

      - name: Run BNB and USDT payment mock tests
        run: |
          forge test \
            --match-contract '^VOINPresalePaymentsDraftTest$' \
            -vvv

      - name: Run adversarial and fuzz mock tests
        run: |
          forge test \
            --match-contract '^VOINPresalePaymentsAdversarialTest$' \
            -vvv

      - name: Run pinned-block BNB mainnet fork tests
        run: |
          forge test \
            --match-contract '^VOINPresalePaymentsForkTest$' \
            -vvv
