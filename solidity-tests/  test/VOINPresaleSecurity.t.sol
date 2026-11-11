// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../src/VOINPresaleTestnet.sol";

// Tes Foundry untuk EVM lokal.
// Belum dijalankan di sini. Bukan laporan audit.
interface Vm {
    function chainId(uint256) external;
    function warp(uint256) external;
    function deal(address, uint256) external;
    function prank(address) external;
    function expectRevert(bytes calldata) external;
}

// Khusus tes batas batch.
// Jangan deploy kontrak bantu ini ke jaringan publik.
contract BoundaryFixture is VOINPresaleTestnet {
    function seedAllocation(uint256 amount) external {
        totalAllocated = amount;
    }
}

contract RefundProbe {
    VOINPresaleTestnet public sale;

    bool public rejectRefund;
    bool public attemptReentry;
    bool public reentrySucceeded;
    bool public reentryGuardMatched;

    constructor(VOINPresaleTestnet s) {
        sale = s;
    }

    function configure(
        bool reject,
        bool reenter
    ) external {
        rejectRefund = reject;
        attemptReentry = reenter;
    }

    function purchase(uint256 units) external payable {
        sale.buyExactTokens{value: msg.value}(units);
    }

    receive() external payable {
        if (rejectRefund) {
            revert("Reject refund");
        }

        if (attemptReentry) {
            (bool ok, bytes memory result) =
                address(sale).call(
                    abi.encodeWithSelector(
                        sale.buyExactTokens.selector,
                        1 ether
                    )
                );

            reentrySucceeded = ok;

            reentryGuardMatched =
                keccak256(result) ==
                keccak256(
                    abi.encodeWithSignature(
                        "Error(string)",
                        "Reentrant call"
                    )
                );
        }
    }
}

contract VOINPresaleSecurityTest {
    Vm constant vm = Vm(
        address(
            uint160(
                uint256(
                    keccak256("hevm cheat code")
                )
            )
        )
    );

    VOINPresaleTestnet sale;
    address constant buyer = address(0xBEEF);

    function setUp() public {
        vm.chainId(97);
        vm.warp(1800000000);

        vm.deal(address(this), 100 ether);
        vm.deal(buyer, 10 ether);

        sale = new VOINPresaleTestnet();
    }

    function testExactPaymentRecordsAllocation() public {
        (uint256 cost, ) =
            sale.quoteExactTokens(1 ether);

        vm.prank(buyer);
        sale.buyExactTokens{value: cost}(1 ether);

        require(
            sale.allocations(buyer) == 1 ether,
            "allocation"
        );
        require(
            sale.totalAllocated() == 1 ether,
            "total"
        );
        require(
            sale.totalPaidWei() == cost,
            "paid"
        );
        require(
            address(sale).balance == cost,
            "balance"
        );
    }

    function testExcessPaymentRefund() public {
        (uint256 cost, ) =
            sale.quoteExactTokens(1 ether);

        uint256 beforeBalance = buyer.balance;

        vm.prank(buyer);
        sale.buyExactTokens{
            value: cost + 1 ether
        }(1 ether);

        require(
            buyer.balance == beforeBalance - cost,
            "refund"
        );
        require(
            address(sale).balance == cost,
            "retained funds"
        );
    }

    function testRefundFailureRollsBackAllAccounting()
        public
    {
        RefundProbe probe = new RefundProbe(sale);
        probe.configure(true, false);

        (uint256 cost, ) =
            sale.quoteExactTokens(1 ether);

        vm.expectRevert(bytes("Refund failed"));

        probe.purchase{
            value: cost + 1 ether
        }(1 ether);

        require(
            sale.allocations(address(probe)) == 0,
            "allocation rollback"
        );
        require(
            sale.totalAllocated() == 0,
            "total rollback"
        );
        require(
            sale.totalPaidWei() == 0,
            "payment rollback"
        );
        require(
            address(sale).balance == 0,
            "balance rollback"
        );
    }

    function testRefundCannotReenterPurchase() public {
        RefundProbe probe = new RefundProbe(sale);
        probe.configure(false, true);

        (uint256 cost, ) =
            sale.quoteExactTokens(1 ether);

        probe.purchase{
            value: cost + 1 ether
        }(1 ether);

        require(
            !probe.reentrySucceeded(),
            "unexpected reentry"
        );
        require(
            probe.reentryGuardMatched(),
            "must fail at reentrancy guard"
        );
        require(
            sale.totalAllocated() == 1 ether,
            "extra allocation"
        );
        require(
            sale.allocations(address(probe)) == 1 ether,
            "buyer allocation"
        );
    }

    function testPauseAndResume() public {
        sale.setPaused(true);

        vm.expectRevert(
            bytes("Sale closed or paused")
        );
        vm.prank(buyer);
        sale.buyExactTokens(1 ether);

        sale.setPaused(false);

        require(
            sale.saleOpen(),
            "resume"
        );
    }

    function testDeadlineClosesSale() public {
        vm.warp(sale.SALE_END());

        require(
            !sale.saleOpen(),
            "deadline"
        );

        vm.expectRevert(
            bytes("Sale closed or paused")
        );
        vm.prank(buyer);
        sale.buyExactTokens(1 ether);
    }

    function testNonTreasuryCannotPauseOrWithdraw()
        public
    {
        vm.expectRevert(bytes("Treasury only"));
        vm.prank(buyer);
        sale.setPaused(true);

        vm.expectRevert(bytes("Treasury only"));
        vm.prank(buyer);
        sale.withdrawTestFunds();
    }

    function testBatchBoundaryPriceAndAdvance() public {
        BoundaryFixture fixture =
            new BoundaryFixture();

        fixture.seedAllocation(
            fixture.BATCH_SIZE() - 1 ether
        );

        (uint256 cost, uint256 usd) =
            fixture.quoteExactTokens(2 ether);

        require(
            usd == 3e16,
            "blended quote"
        );

        vm.prank(buyer);
        fixture.buyExactTokens{
            value: cost
        }(2 ether);

        require(
            fixture.currentBatch() == 2,
            "batch advance"
        );
        require(
            fixture.currentPriceUsdCents() == 2,
            "batch2 price"
        );
    }

    function testFinalCapClosesSale() public {
        BoundaryFixture fixture =
            new BoundaryFixture();

        fixture.seedAllocation(
            fixture.PRESALE_CAP() - 1 ether
        );

        (uint256 cost, uint256 usd) =
            fixture.quoteExactTokens(1 ether);

        require(
            usd == 1e17,
            "batch10 price"
        );

        vm.prank(buyer);
        fixture.buyExactTokens{
            value: cost
        }(1 ether);

        require(
            !fixture.saleOpen(),
            "cap closes sale"
        );
        require(
            fixture.currentBatch() == 10,
            "final batch"
        );
    }

    receive() external payable {}
}
