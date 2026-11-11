// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ISOLATED MOCK TESTS ONLY. Not an audit, deployment or real payment.
// Place next to VOINPresalePaymentsDraftTest-20261111-1752.t.sol
// directly inside solidity-tests (not inside a new subfolder).
import {VOINPresalePaymentsDraft} from "./src/VOINPresalePaymentsDraft-20261111-1733.sol";
import {VmPaymentsDraft, VoinMockUsdFeed, VoinMockUsdt} from "./VOINPresalePaymentsDraftTest-20261111-1752.t.sol";

contract VoinRefundAttackReceiver {
    VOINPresalePaymentsDraft public immutable sale;
    bool public rejectRefund;
    bool public attemptReentry;
    bool public reentrySucceeded;
    bool public callbackReached;
    constructor(VOINPresalePaymentsDraft sale_) { sale = sale_; }
    function configure(bool reject_, bool reenter_) external {
        rejectRefund = reject_; attemptReentry = reenter_;
    }
    function buy(uint256 amount, uint256 maximum, uint256 deadline) external payable {
        sale.buyWithBnb{value: msg.value}(amount, maximum, deadline);
    }
    receive() external payable {
        callbackReached = true;
        require(!rejectRefund, "Receiver rejects refund");
        if (attemptReentry) {
            (bool ok,) = address(sale).call(
                abi.encodeWithSelector(sale.buyWithBnb.selector, 1e18, type(uint256).max, block.timestamp + 60)
            );
            reentrySucceeded = ok;
        }
    }
}

contract VoinRejectingTreasury {
    receive() external payable { revert("Treasury rejects BNB"); }
}

contract VOINPresalePaymentsAdversarialTest {
    VmPaymentsDraft private constant vm = VmPaymentsDraft(address(uint160(uint256(keccak256("hevm cheat code")))));
    VOINPresalePaymentsDraft private sale;
    VoinMockUsdFeed private bnbFeed;
    VoinMockUsdFeed private usdtFeed;
    VoinMockUsdt private stable;
    uint256 private constant UNIT = 1e18;
    address payable private constant TREASURY = payable(address(0xBEEF));
    receive() external payable {}

    function setUp() public {
        vm.chainId(97);
        vm.warp(1_800_000_000);
        vm.deal(address(this), 100 ether);
        bnbFeed = new VoinMockUsdFeed(600 * 1e8);
        usdtFeed = new VoinMockUsdFeed(1e8);
        stable = new VoinMockUsdt(18);
        sale = deploy(TREASURY);
        stable.mint(address(this), 100_000_000 * UNIT);
        stable.approve(address(sale), type(uint256).max);
        sale.setPaused(false);
    }

    function deploy(address payable treasury_) private returns (VOINPresalePaymentsDraft) {
        return new VOINPresalePaymentsDraft(
            97, address(this), treasury_, address(stable),
            address(bnbFeed), address(usdtFeed), 3600, 3600, 95e16, 105e16
        );
    }

    function testRefundCallbackCannotReenterPurchase() public {
        VoinRefundAttackReceiver attacker = new VoinRefundAttackReceiver(sale);
        attacker.configure(false, true);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        attacker.buy{value: cost + 1 ether}(100 * UNIT, cost, block.timestamp + 60);
        require(attacker.callbackReached(), "Refund callback not exercised");
        require(!attacker.reentrySucceeded(), "Reentry unexpectedly succeeded");
        require(sale.allocations(address(attacker)) == 100 * UNIT, "Unexpected allocation");
        require(sale.totalAllocated() == 100 * UNIT, "Unexpected total allocation");
        require(sale.totalBnbPaid() == cost && address(sale).balance == cost, "BNB mismatch");
        require(address(attacker).balance == 1 ether, "Refund amount mismatch");
    }

    function testRejectingRefundRollsBackEntirePurchase() public {
        VoinRefundAttackReceiver receiver = new VoinRefundAttackReceiver(sale);
        receiver.configure(true, false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        uint256 beforeBuyer = address(this).balance;
        vm.expectRevert(bytes("Excess BNB refund failed"));
        receiver.buy{value: cost + 1 ether}(100 * UNIT, cost, block.timestamp + 60);
        require(sale.allocations(address(receiver)) == 0, "Allocation was not rolled back");
        require(sale.totalAllocated() == 0 && sale.totalBnbPaid() == 0, "Totals changed");
        require(address(sale).balance == 0 && address(receiver).balance == 0, "Funds moved");
        require(address(this).balance == beforeBuyer, "Buyer funds not restored");
    }

    function testRejectingReceiverCanBuyWithExactPayment() public {
        VoinRefundAttackReceiver receiver = new VoinRefundAttackReceiver(sale);
        receiver.configure(true, false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        receiver.buy{value: cost}(100 * UNIT, cost, block.timestamp + 60);
        require(!receiver.callbackReached(), "Exact payment should not invoke refund");
        require(sale.allocations(address(receiver)) == 100 * UNIT, "Exact payment failed");
    }

    function testFailedTreasuryWithdrawalPreservesFunds() public {
        VoinRejectingTreasury rejecting = new VoinRejectingTreasury();
        VOINPresalePaymentsDraft other = deploy(payable(address(rejecting)));
        other.setPaused(false);
        (uint256 cost,) = other.quoteBnb(100 * UNIT);
        other.buyWithBnb{value: cost}(100 * UNIT, cost, block.timestamp + 60);
        vm.expectRevert(bytes("BNB withdrawal failed"));
        other.withdrawBnb(cost);
        require(address(other).balance == cost, "Failed withdrawal lost funds");
        require(other.totalBnbPaid() == cost, "Historical payment count changed");
        require(other.allocations(address(this)) == 100 * UNIT, "Allocation changed");
    }

    function testStaleUsdtQuoteRejected() public {
        usdtFeed.set(1e8, block.timestamp - 3601);
        vm.expectRevert(bytes("Stale oracle price"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
        require(sale.totalAllocated() == 0, "Stale purchase recorded");
    }

    function testNegativeUsdtPriceRejected() public {
        usdtFeed.set(-1, block.timestamp);
        vm.expectRevert(bytes("Nonpositive oracle price"));
        sale.quoteUsdt(100 * UNIT);
    }

    function testFutureUsdtTimestampRejected() public {
        usdtFeed.set(1e8, block.timestamp + 1);
        vm.expectRevert(bytes("Invalid oracle timestamp"));
        sale.quoteUsdt(100 * UNIT);
    }

    function testMissingUsdtTimestampRejected() public {
        usdtFeed.set(1e8, 0);
        vm.expectRevert(bytes("Invalid oracle timestamp"));
        sale.quoteUsdt(100 * UNIT);
    }

    function testUsdtAboveUpperPriceBoundRejected() public {
        usdtFeed.set(106_000_000, block.timestamp);
        vm.expectRevert(bytes("USDT outside bounds"));
        sale.quoteUsdt(100 * UNIT);
    }

    function testPausedSaleRejectsBothPaymentMethods() public {
        sale.setPaused(true);
        vm.expectRevert(bytes("Sale closed or paused"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
        vm.expectRevert(bytes("Sale closed or paused"));
        sale.buyWithBnb{value: 1 ether}(100 * UNIT, 1 ether, block.timestamp + 60);
        require(sale.totalAllocated() == 0, "Paused purchase changed state");
    }

    function testChangedBatchPriceCannotExceedBuyerUsdtLimit() public {
        uint256 batch = sale.BATCH_SIZE();
        (uint256 oldQuote,) = sale.quoteUsdt(100 * UNIT);
        (uint256 batchCost,) = sale.quoteUsdt(batch);
        sale.buyWithUsdt(batch, batchCost, block.timestamp + 60);
        require(sale.currentBatch() == 2, "Batch did not change");
        uint256 beforeTokens = stable.balanceOf(address(this));
        vm.expectRevert(bytes("Payment exceeds buyer limit"));
        sale.buyWithUsdt(100 * UNIT, oldQuote, block.timestamp + 60);
        require(sale.totalAllocated() == batch, "Stale quote altered allocation");
        require(stable.balanceOf(address(this)) == beforeTokens, "Stale quote took tokens");
    }

    function testBnbPriceDropCannotExceedBuyerLimit() public {
        (uint256 oldQuote,) = sale.quoteBnb(100 * UNIT);
        bnbFeed.set(300 * 1e8, block.timestamp);
        vm.expectRevert(bytes("Payment exceeds buyer limit"));
        sale.buyWithBnb{value: oldQuote}(100 * UNIT, oldQuote, block.timestamp + 60);
        require(sale.totalAllocated() == 0, "Price movement recorded purchase");
    }

    function testMixedPaymentsShareSameAllocationCounter() public {
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        sale.buyWithBnb{value: cost}(100 * UNIT, cost, block.timestamp + 60);
        (uint256 tokenCost,) = sale.quoteUsdt(200 * UNIT);
        sale.buyWithUsdt(200 * UNIT, tokenCost, block.timestamp + 60);
        require(sale.allocations(address(this)) == 300 * UNIT, "Buyer total mismatch");
        require(sale.totalAllocated() == 300 * UNIT, "Global total mismatch");
        require(sale.totalBnbPaid() == cost, "BNB counter wrong");
        require(sale.totalUsdtPaid() == tokenCost, "USDT counter wrong");
    }

    function testFuzzBnbRoundingAndRefundConservation(uint64 seed) public {
        // Small enough for batch1 and test funding, includes fractional units.
        uint256 amount = uint256(seed) % (10_000 * UNIT) + 1;
        (uint256 cost, uint256 usdCost) = sale.quoteBnb(amount);
        require(cost * 600 >= usdCost, "BNB quote undercharges");
        if (cost > 0) require((cost - 1) * 600 < usdCost, "BNB quote not minimal");
        uint256 beforeBalance = address(this).balance;
        sale.buyWithBnb{value: cost + 1 ether}(amount, cost, block.timestamp + 60);
        require(address(this).balance == beforeBalance - cost, "Buyer conservation failed");
        require(address(sale).balance == cost, "Contract conservation failed");
        require(sale.totalAllocated() == amount, "Allocation mismatch");
    }

    function testFuzzUsdtDebitAndAllocationConservation(uint64 seed) public {
        uint256 amount = uint256(seed) % (10_000 * UNIT) + 1;
        (uint256 cost,) = sale.quoteUsdt(amount);
        uint256 beforeBalance = stable.balanceOf(address(this));
        sale.buyWithUsdt(amount, cost, block.timestamp + 60);
        require(stable.balanceOf(address(this)) == beforeBalance - cost, "Buyer debit mismatch");
        require(stable.balanceOf(address(sale)) == cost, "Contract credit mismatch");
        require(sale.allocations(address(this)) == amount, "Buyer allocation mismatch");
        require(sale.totalAllocated() == amount, "Total allocation mismatch");
    }
}
