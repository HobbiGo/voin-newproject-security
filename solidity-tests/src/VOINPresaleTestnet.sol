// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// TESTNET ONLY. Not audited or production-ready.
/// Records purchase allocations, not native VOIN coins.
/// Does not implement coin distribution or claims.
contract VOINPresaleTestnet {
    uint256 public constant CHAIN_ID = 97;
    uint256 public constant TOKEN_UNIT = 1e18;

    uint256 public constant BATCH_SIZE =
        13_000_000 * TOKEN_UNIT;

    uint256 public constant PRESALE_CAP =
        130_000_000 * TOKEN_UNIT;

    // Reference only. This contract does not create this supply.
    uint256 public constant PLANNED_TOTAL_SUPPLY =
        260_000_000 * TOKEN_UNIT;

    // 1 February 2027, 00:00 WIB.
    uint256 public constant SALE_END = 1801414800;

    // TEST EXCHANGE RATE ONLY:
    // Assume 1 tBNB = USD 600.
    // This is NOT a market price or production oracle.
    uint256 public constant MOCK_BNB_USD_CENTS = 60000;

    address payable public immutable testTreasury;

    uint256 public totalAllocated;
    uint256 public totalPaidWei;

    mapping(address => uint256) public allocations;

    bool public paused;
    uint256 private lockState = 1;

    event Purchased(
        address indexed buyer,
        uint256 tokenUnits,
        uint256 paidWei,
        uint256 totalAllocatedAfter
    );

    event PauseChanged(bool paused);

    event TestFundsWithdrawn(uint256 amountWei);

    modifier nonReentrant() {
        require(lockState == 1, "Reentrant call");
        lockState = 2;
        _;
        lockState = 1;
    }

    modifier onlyTreasury() {
        require(
            msg.sender == testTreasury,
            "Treasury only"
        );
        _;
    }

    constructor() {
        require(
            block.chainid == CHAIN_ID,
            "BSC TESTNET ONLY: chain 97"
        );

        require(
            block.timestamp < SALE_END,
            "Sale end has passed"
        );

        testTreasury = payable(msg.sender);
    }

    function currentBatch()
        public
        view
        returns (uint256)
    {
        if (totalAllocated == PRESALE_CAP) {
            return 10;
        }

        return totalAllocated / BATCH_SIZE + 1;
    }

    function currentPriceUsdCents()
        external
        view
        returns (uint256)
    {
        // Batch 1 = 1 cent; batch 10 = 10 cents.
        return currentBatch();
    }

    function saleOpen()
        public
        view
        returns (bool)
    {
        return
            !paused &&
            block.timestamp < SALE_END &&
            totalAllocated < PRESALE_CAP;
    }

    /// tokenUnits uses 18 decimals.
    /// requiredWei is the tBNB cost at the MOCK rate.
    /// usdCost18 is the USD cost with 18 decimals.
    /// A purchase crossing a batch boundary uses each
    /// batch's respective price.
    function quoteExactTokens(uint256 tokenUnits)
        public
        view
        returns (
            uint256 requiredWei,
            uint256 usdCost18
        )
    {
        require(
            tokenUnits > 0,
            "Zero allocation"
        );

        require(
            tokenUnits <= PRESALE_CAP - totalAllocated,
            "Exceeds remaining cap"
        );

        uint256 cursor = totalAllocated;
        uint256 left = tokenUnits;

        while (left > 0) {
            uint256 batch =
                cursor / BATCH_SIZE + 1;

            uint256 batchRemaining =
                batch * BATCH_SIZE - cursor;

            uint256 take =
                left < batchRemaining
                    ? left
                    : batchRemaining;

            uint256 priceUsd18 =
                batch * 1e16;

            usdCost18 += ceilDiv(
                take * priceUsd18,
                TOKEN_UNIT
            );

            cursor += take;
            left -= take;
        }

        requiredWei = ceilDiv(
            usdCost18 * 100,
            MOCK_BNB_USD_CENTS
        );
    }

    /// Requests an exact allocation of token units.
    /// No VOIN coins are transferred.
    /// Insufficient payment reverts.
    /// Excess payment is refunded atomically.
    function buyExactTokens(uint256 tokenUnits)
        external
        payable
        nonReentrant
    {
        require(
            saleOpen(),
            "Sale closed or paused"
        );

        (uint256 requiredWei, ) =
            quoteExactTokens(tokenUnits);

        require(
            msg.value >= requiredWei,
            "Insufficient test BNB"
        );

        allocations[msg.sender] += tokenUnits;
        totalAllocated += tokenUnits;
        totalPaidWei += requiredWei;

        emit Purchased(
            msg.sender,
            tokenUnits,
            requiredWei,
            totalAllocated
        );

        uint256 refund =
            msg.value - requiredWei;

        if (refund > 0) {
            (bool ok, ) =
                payable(msg.sender).call{
                    value: refund
                }("");

            require(ok, "Refund failed");
        }
    }

    function setPaused(bool value)
        external
        onlyTreasury
    {
        paused = value;
        emit PauseChanged(value);
    }

    /// Deployer may recover test funds.
    /// Not a production treasury or refund policy.
    function withdrawTestFunds()
        external
        onlyTreasury
        nonReentrant
    {
        uint256 amount =
            address(this).balance;

        require(amount > 0, "No funds");

        (bool ok, ) =
            testTreasury.call{
                value: amount
            }("");

        require(ok, "Withdrawal failed");

        emit TestFundsWithdrawn(amount);
    }

    function ceilDiv(
        uint256 numerator,
        uint256 denominator
    )
        private
        pure
        returns (uint256)
    {
        return numerator == 0
            ? 0
            : (numerator - 1) / denominator + 1;
    }

    receive() external payable {
        revert("Use buyExactTokens");
    }

    fallback() external payable {
        revert("Unknown function");
    }
}
