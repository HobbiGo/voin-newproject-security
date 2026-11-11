// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FORK TEST DRAFT: not yet successfully executed in full.
// Local simulation only. No signed mainnet transactions.
// Upload directly inside solidity-tests.
// No private key or wallet connection required.

import {
    VOINPresalePaymentsDraft,
    IVoinUsdFeed
} from "./src/VOINPresalePaymentsDraft-20261111-1733.sol";

interface VmVoinFork {
    function createSelectFork(
        string calldata url,
        uint256 blockNumber
    ) external returns (uint256);

    function envOr(
        string calldata name,
        string calldata defaultValue
    ) external returns (string memory);

    function deal(address account, uint256 balance) external;

    function load(
        address target,
        bytes32 slot
    ) external view returns (bytes32);

    function store(
        address target,
        bytes32 slot,
        bytes32 value
    ) external;

    function expectRevert() external;
}

interface IVoinForkToken {
    function decimals() external view returns (uint8);

    function balanceOf(
        address account
    ) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool);
}

contract VOINPresalePaymentsForkTest {
    VmVoinFork private constant vm = VmVoinFork(
        address(
            uint160(
                uint256(keccak256("hevm cheat code"))
            )
        )
    );

    uint256 private constant PINNED_BLOCK = 132960716;
    uint256 private constant PINNED_TIMESTAMP = 1794396699;

    address private constant USDT = address(
        bytes20(hex"55d398326f99059ff775485246999027b3197955")
    );

    address private constant BNB_USD = address(
        bytes20(hex"0567f2323251f0aab15c8dfb1967e4e8a7d42aee")
    );

    address private constant USDT_USD = address(
        bytes20(hex"b97ad0e74fa7d920791e90258a6e2085088b4320")
    );

    address payable private constant LOCAL_TREASURY =
        payable(address(0xBEEF));

    uint256 private constant UNIT = 1e18;

    VOINPresalePaymentsDraft private sale;
    IVoinForkToken private token;

    receive() external payable {}

    function setUp() public {
        string memory rpc = vm.envOr(
            "BSC_RPC_URL",
            string("https://bsc-rpc.publicnode.com")
        );

        vm.createSelectFork(rpc, PINNED_BLOCK);

        require(
            block.chainid == 56,
            "Fork must be BNB mainnet"
        );

        require(
            block.number == PINNED_BLOCK,
            "Unexpected block"
        );

        require(
            block.timestamp == PINNED_TIMESTAMP,
            "Unexpected timestamp"
        );

        require(
            USDT.code.length > 0 &&
            BNB_USD.code.length > 0 &&
            USDT_USD.code.length > 0,
            "Missing fork code"
        );

        token = IVoinForkToken(USDT);

        require(
            token.decimals() == 18,
            "Unexpected USDT precision"
        );

        require(
            IVoinUsdFeed(BNB_USD).decimals() == 8,
            "Unexpected BNB feed precision"
        );

        require(
            IVoinUsdFeed(USDT_USD).decimals() == 8,
            "Unexpected USDT feed precision"
        );

        // Test-only freshness parameters for this exact block.
        // These are NOT production recommendations.
        uint256 bnbAge = checkedAge(BNB_USD);
        uint256 usdtAge = checkedAge(USDT_USD);

        sale = new VOINPresalePaymentsDraft(
            56,
            address(this),
            LOCAL_TREASURY,
            USDT,
            BNB_USD,
            USDT_USD,
            bnbAge + 1,
            usdtAge + 1,
            95e16,
            105e16
        );

        vm.deal(address(this), 10 ether);
    }

    function checkedAge(
        address feed
    ) private view returns (uint256) {
        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = IVoinUsdFeed(feed).latestRoundData();

        require(
            answer > 0,
            "Nonpositive real feed answer"
        );

        require(
            updatedAt > 0 &&
            updatedAt <= block.timestamp,
            "Invalid real feed timestamp"
        );

        return block.timestamp - updatedAt;
    }

    function feedPrice18(
        address feed
    ) private view returns (uint256) {
        (, int256 answer, , , ) =
            IVoinUsdFeed(feed).latestRoundData();

        require(answer > 0, "Invalid price");

        return uint256(answer) * 1e10;
    }

    function ceilDiv(
        uint256 numerator,
        uint256 denominator
    ) private pure returns (uint256) {
        return
            numerator / denominator +
            (numerator % denominator == 0 ? 0 : 1);
    }

    // Synthetic funding in the local fork ONLY.
    // Does not transfer real tokens or change mainnet state.
    // Existing mainnet balances at the test address are allowed.
    function fundLocalUsdt(uint256 amount) private {
        if (token.balanceOf(address(this)) == amount) {
            return;
        }

        for (uint256 slot = 0; slot < 32; slot++) {
            bytes32 key = keccak256(
                abi.encode(address(this), slot)
            );

            bytes32 beforeValue = vm.load(USDT, key);

            vm.store(USDT, key, bytes32(amount));

            if (token.balanceOf(address(this)) == amount) {
                return;
            }

            vm.store(USDT, key, beforeValue);
        }

        revert(
            "Unable to locate balance mapping; inspect token layout"
        );
    }

    function testForkStartsPausedWithExpectedDependencies()
        public
        view
    {
        require(sale.paused(), "Must start paused");

        require(
            address(sale.usdt()) == USDT,
            "Wrong token"
        );

        require(
            address(sale.bnbUsdFeed()) == BNB_USD,
            "Wrong BNB feed"
        );

        require(
            address(sale.usdtUsdFeed()) == USDT_USD,
            "Wrong USDT feed"
        );

        require(
            sale.usdtScale() == UNIT,
            "Wrong token scale"
        );
    }

    function testForkQuotesMatchRealFeedAnswers()
        public
        view
    {
        uint256 amount = 100 * UNIT;

        (
            uint256 bnbCost,
            uint256 bnbUsdCost
        ) = sale.quoteBnb(amount);

        (
            uint256 usdtCost,
            uint256 usdtUsdCost
        ) = sale.quoteUsdt(amount);

        require(
            bnbUsdCost == UNIT &&
            usdtUsdCost == UNIT,
            "Wrong batch-one USD cost"
        );

        require(
            bnbCost ==
                ceilDiv(
                    UNIT * UNIT,
                    feedPrice18(BNB_USD)
                ),
            "BNB quote mismatch"
        );

        require(
            usdtCost ==
                ceilDiv(
                    UNIT * UNIT,
                    feedPrice18(USDT_USD)
                ),
            "USDT quote mismatch"
        );
    }

    function testForkLocalBnbPurchaseRefundAndTreasuryWithdrawal()
        public
    {
        sale.setPaused(false);

        (uint256 cost, ) = sale.quoteBnb(100 * UNIT);

        uint256 beforeBuyer = address(this).balance;
        uint256 beforeTreasury = LOCAL_TREASURY.balance;

        sale.buyWithBnb{value: cost + 1 ether}(
            100 * UNIT,
            cost,
            block.timestamp + 60
        );

        require(
            address(this).balance == beforeBuyer - cost,
            "Incorrect refund"
        );

        require(
            address(sale).balance == cost &&
            sale.totalBnbPaid() == cost,
            "BNB mismatch"
        );

        require(
            sale.allocations(address(this)) == 100 * UNIT,
            "Allocation mismatch"
        );

        sale.withdrawBnb(cost);

        require(
            address(sale).balance == 0,
            "BNB withdrawal incomplete"
        );

        require(
            LOCAL_TREASURY.balance ==
                beforeTreasury + cost,
            "Treasury mismatch"
        );
    }

    function testForkRealUsdtCodeApprovalPurchaseAndWithdrawal()
        public
    {
        sale.setPaused(false);

        (uint256 cost, ) = sale.quoteUsdt(100 * UNIT);

        fundLocalUsdt(cost + UNIT);

        require(
            token.approve(address(sale), cost),
            "Approve failed"
        );

        require(
            token.allowance(address(this), address(sale))
                == cost,
            "Wrong allowance"
        );

        uint256 beforeSale =
            token.balanceOf(address(sale));

        uint256 beforeTreasury =
            token.balanceOf(LOCAL_TREASURY);

        sale.buyWithUsdt(
            100 * UNIT,
            cost,
            block.timestamp + 60
        );

        require(
            token.balanceOf(address(this)) == UNIT,
            "Wrong buyer debit"
        );

        require(
            token.balanceOf(address(sale)) ==
                beforeSale + cost,
            "Wrong sale credit"
        );

        require(
            sale.totalUsdtPaid() == cost,
            "Wrong payment counter"
        );

        require(
            sale.allocations(address(this)) == 100 * UNIT,
            "Wrong allocation"
        );

        sale.withdrawUsdt(cost);

        require(
            token.balanceOf(address(sale)) == beforeSale,
            "USDT withdrawal incomplete"
        );

        require(
            token.balanceOf(LOCAL_TREASURY) ==
                beforeTreasury + cost,
            "Wrong treasury credit"
        );
    }

    function testForkMissingAllowanceRevertsAndRollsBack()
        public
    {
        sale.setPaused(false);

        (uint256 cost, ) = sale.quoteUsdt(100 * UNIT);

        fundLocalUsdt(cost);

        require(
            token.approve(address(sale), 0),
            "Allowance reset failed"
        );

        vm.expectRevert();

        sale.buyWithUsdt(
            100 * UNIT,
            cost,
            block.timestamp + 60
        );

        require(
            sale.totalAllocated() == 0 &&
            sale.totalUsdtPaid() == 0,
            "Counters changed"
        );

        require(
            token.balanceOf(address(this)) == cost,
            "Buyer lost tokens"
        );

        require(
            token.balanceOf(address(sale)) == 0,
            "Sale retained tokens"
        );
    }

    function testForkMixedPaymentAllocationsStayConsistent()
        public
    {
        sale.setPaused(false);

        (uint256 bnbCost, ) =
            sale.quoteBnb(100 * UNIT);

        sale.buyWithBnb{value: bnbCost}(
            100 * UNIT,
            bnbCost,
            block.timestamp + 60
        );

        (uint256 tokenCost, ) =
            sale.quoteUsdt(200 * UNIT);

        fundLocalUsdt(tokenCost);

        require(
            token.approve(address(sale), tokenCost),
            "Approve failed"
        );

        sale.buyWithUsdt(
            200 * UNIT,
            tokenCost,
            block.timestamp + 60
        );

        require(
            sale.totalAllocated() == 300 * UNIT,
            "Global allocation mismatch"
        );

        require(
            sale.allocations(address(this)) == 300 * UNIT,
            "Buyer allocation mismatch"
        );

        require(
            sale.totalBnbPaid() == bnbCost &&
            sale.totalUsdtPaid() == tokenCost,
            "Payment totals mismatch"
        );
    }
}
