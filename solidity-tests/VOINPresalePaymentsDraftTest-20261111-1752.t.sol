// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Isolated tests with mocks. NOT mainnet transactions or an audit.
import {VOINPresalePaymentsDraft} from "../src/VOINPresalePaymentsDraft-20261111-1733.sol";

interface VmPaymentsDraft {
    function chainId(uint256) external;
    function warp(uint256) external;
    function deal(address, uint256) external;
    function prank(address) external;
    function expectRevert(bytes calldata) external;
}

contract VoinMockUsdFeed {
    uint8 public constant decimals = 8;
    int256 public answer;
    uint256 public updatedAt;
    constructor(int256 price) { set(price, block.timestamp); }
    function set(int256 price, uint256 timestamp) public {
        answer = price; updatedAt = timestamp;
    }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract VoinMockUsdt {
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public feeEnabled;
    constructor(uint8 precision) { decimals = precision; }
    function mint(address who, uint256 amount) external { balanceOf[who] += amount; }
    function setFee(bool value) external { feeEnabled = value; }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount; return true;
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        move(msg.sender, to, amount); return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Allowance too low");
        allowance[from][msg.sender] -= amount;
        move(from, to, amount); return true;
    }
    function move(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "Balance too low");
        balanceOf[from] -= amount;
        balanceOf[to] += feeEnabled ? amount - amount / 100 : amount;
    }
}

contract VOINPresalePaymentsDraftTest {
    VmPaymentsDraft private constant vm = VmPaymentsDraft(address(uint160(uint256(keccak256("hevm cheat code")))));
    VOINPresalePaymentsDraft private sale;
    VoinMockUsdFeed private bnbFeed;
    VoinMockUsdFeed private usdtFeed;
    VoinMockUsdt private stable;
    address payable private constant TREASURY = payable(address(0xBEEF));
    uint256 private constant UNIT = 1e18;

    receive() external payable {}

    function setUp() public {
        vm.chainId(97);
        vm.warp(1_800_000_000);
        vm.deal(address(this), 100 ether);
        bnbFeed = new VoinMockUsdFeed(600 * 1e8);
        usdtFeed = new VoinMockUsdFeed(1e8);
        stable = new VoinMockUsdt(18);
        sale = deploy(address(stable));
        stable.mint(address(this), 100_000_000 * UNIT);
        stable.approve(address(sale), type(uint256).max);
    }

    function deploy(address token) private returns (VOINPresalePaymentsDraft) {
        return new VOINPresalePaymentsDraft(
            97, address(this), TREASURY, token,
            address(bnbFeed), address(usdtFeed),
            3600, 3600, 95e16, 105e16
        );
    }

    function testInitiallyPaused() public {
        require(sale.paused(), "Must start paused");
        require(!sale.saleOpen(), "Must not open on deploy");
        vm.expectRevert(bytes("Sale closed or paused"));
        sale.buyWithBnb{value: 1 ether}(100 * UNIT, 1 ether, block.timestamp + 60);
    }

    function testBnbExactPaymentAndAllocation() public {
        sale.setPaused(false);
        (uint256 cost, uint256 usd) = sale.quoteBnb(100 * UNIT);
        require(usd == UNIT, "100 tokens must cost USD1 in batch1");
        sale.buyWithBnb{value: cost}(100 * UNIT, cost, block.timestamp + 60);
        require(sale.allocations(address(this)) == 100 * UNIT, "Allocation mismatch");
        require(sale.totalBnbPaid() == cost, "BNB accounting mismatch");
        require(address(sale).balance == cost, "BNB custody mismatch");
    }

    function testBnbExcessRefund() public {
        sale.setPaused(false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        uint256 beforeBalance = address(this).balance;
        sale.buyWithBnb{value: cost + 1 ether}(100 * UNIT, cost, block.timestamp + 60);
        require(address(this).balance == beforeBalance - cost, "Refund mismatch");
    }

    function testBnbInsufficientPaymentReverts() public {
        sale.setPaused(false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        vm.expectRevert(bytes("Insufficient BNB"));
        sale.buyWithBnb{value: cost - 1}(100 * UNIT, cost, block.timestamp + 60);
        require(sale.totalAllocated() == 0, "Must not record failed purchase");
    }

    function testUsdtExactPaymentAndAllocation() public {
        sale.setPaused(false);
        (uint256 cost, uint256 usd) = sale.quoteUsdt(100 * UNIT);
        require(cost == UNIT && usd == UNIT, "USD1 expected");
        sale.buyWithUsdt(100 * UNIT, cost, block.timestamp + 60);
        require(sale.allocations(address(this)) == 100 * UNIT, "USDT allocation mismatch");
        require(sale.totalUsdtPaid() == cost, "USDT accounting mismatch");
        require(stable.balanceOf(address(sale)) == cost, "USDT custody mismatch");
    }

    function testUsdtSixDecimalPrecision() public {
        VoinMockUsdt six = new VoinMockUsdt(6);
        VOINPresalePaymentsDraft other = deploy(address(six));
        six.mint(address(this), 100 * 1e6);
        six.approve(address(other), type(uint256).max);
        other.setPaused(false);
        (uint256 cost,) = other.quoteUsdt(100 * UNIT);
        require(cost == 1e6, "Wrong 6-decimal quote");
        other.buyWithUsdt(100 * UNIT, cost, block.timestamp + 60);
        require(six.balanceOf(address(other)) == 1e6, "Wrong 6-decimal receipt");
    }

    function testUsdtMissingAllowanceReverts() public {
        sale.setPaused(false);
        stable.approve(address(sale), 0);
        vm.expectRevert(bytes("Allowance too low"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
        require(sale.totalAllocated() == 0, "Failed transfer changed allocations");
    }

    function testFeeOnTransferTokenRollsBack() public {
        sale.setPaused(false);
        stable.setFee(true);
        uint256 originalBalance = stable.balanceOf(address(this));
        vm.expectRevert(bytes("USDT amount received differs"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
        require(sale.totalAllocated() == 0 && sale.totalUsdtPaid() == 0, "Accounting not reverted");
        require(stable.balanceOf(address(this)) == originalBalance, "Token debit not reverted");
        require(stable.balanceOf(address(sale)) == 0, "Token receipt not reverted");
    }

    function testStaleBnbPriceRejected() public {
        sale.setPaused(false);
        bnbFeed.set(600 * 1e8, block.timestamp - 3601);
        vm.expectRevert(bytes("Stale oracle price"));
        sale.quoteBnb(100 * UNIT);
    }

    function testNonpositiveBnbPriceRejected() public {
        bnbFeed.set(0, block.timestamp);
        vm.expectRevert(bytes("Nonpositive oracle price"));
        sale.quoteBnb(100 * UNIT);
    }

    function testFutureOracleTimestampRejected() public {
        bnbFeed.set(600 * 1e8, block.timestamp + 1);
        vm.expectRevert(bytes("Invalid oracle timestamp"));
        sale.quoteBnb(100 * UNIT);
    }

    function testUsdtDepegRejected() public {
        usdtFeed.set(90_000_000, block.timestamp);
        vm.expectRevert(bytes("USDT outside bounds"));
        sale.quoteUsdt(100 * UNIT);
    }

    function testExpiredQuoteRejected() public {
        sale.setPaused(false);
        vm.expectRevert(bytes("Quote expired"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp - 1);
    }

    function testBnbBuyerPaymentLimitRejected() public {
        sale.setPaused(false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        vm.expectRevert(bytes("Payment exceeds buyer limit"));
        sale.buyWithBnb{value: cost}(100 * UNIT, cost - 1, block.timestamp + 60);
    }

    function testUsdtBuyerPaymentLimitRejected() public {
        sale.setPaused(false);
        vm.expectRevert(bytes("Payment exceeds buyer limit"));
        sale.buyWithUsdt(100 * UNIT, UNIT - 1, block.timestamp + 60);
    }

    function testCrossBatchQuoteUsesBothPrices() public {
        sale.setPaused(false);
        uint256 first = sale.BATCH_SIZE() - UNIT;
        (uint256 cost,) = sale.quoteUsdt(first);
        sale.buyWithUsdt(first, cost, block.timestamp + 60);
        // Last 1 token in batch1 = USD .01; first 1 in batch2 = USD .02.
        require(sale.quoteUsd(2 * UNIT) == 3e16, "Cross-batch quote incorrect");
        (cost,) = sale.quoteUsdt(2 * UNIT);
        sale.buyWithUsdt(2 * UNIT, cost, block.timestamp + 60);
        require(sale.currentBatch() == 2, "Must advance after sold quota");
    }

    function testUnauthorizedPauseRejected() public {
        vm.prank(address(0x1234));
        vm.expectRevert(bytes("Administrator only"));
        sale.setPaused(false);
    }

    function testUnauthorizedWithdrawalRejected() public {
        vm.prank(address(0x1234));
        vm.expectRevert(bytes("Administrator only"));
        sale.withdrawBnb(1);
    }

    function testWithdrawalOnlyToFixedTreasury() public {
        sale.setPaused(false);
        (uint256 cost,) = sale.quoteBnb(100 * UNIT);
        sale.buyWithBnb{value: cost}(100 * UNIT, cost, block.timestamp + 60);
        uint256 beforeTreasury = TREASURY.balance;
        sale.withdrawBnb(cost);
        require(TREASURY.balance == beforeTreasury + cost, "Wrong BNB recipient");
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
        sale.withdrawUsdt(UNIT);
        require(stable.balanceOf(TREASURY) == UNIT, "Wrong USDT recipient");
    }

    function testDeadlineClosesNewPayments() public {
        sale.setPaused(false);
        vm.warp(sale.SALE_END());
        require(!sale.saleOpen(), "Sale must close at deadline");
        vm.expectRevert(bytes("Sale closed or paused"));
        sale.buyWithUsdt(100 * UNIT, UNIT, block.timestamp + 60);
    }

    function testPresaleCapRejectsExcess() public {
        sale.setPaused(false);
        uint256 cap = sale.PRESALE_CAP();
        (uint256 cost,) = sale.quoteUsdt(cap);
        sale.buyWithUsdt(cap, cost, block.timestamp + 60);
        require(sale.totalAllocated() == cap && !sale.saleOpen(), "Cap not enforced");
        vm.expectRevert(bytes("Exceeds remaining cap"));
        sale.quoteUsd(1);
    }
}
