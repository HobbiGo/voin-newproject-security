// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// REVIEW DRAFT ONLY. NOT COMPILED, TESTED, AUDITED OR APPROVED FOR REAL FUNDS.
// Future native VOIN ALLOCATIONS ONLY: no native coins, token distribution,
// delivery guarantee, claims or investor cancellation/refund scheme implemented.
// This is separate from VOINPresaleTestnet. Do not replace the live contract.
// Imports must be pinned to a reviewed OpenZeppelin release before compilation.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVoinUsdFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (
        uint80 roundId, int256 answer, uint256 startedAt,
        uint256 updatedAt, uint80 answeredInRound
    );
}

contract VOINPresalePaymentsDraft is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant UNIT = 1e18;
    uint256 public constant BATCH_SIZE = 13_000_000 * UNIT;
    uint256 public constant PRESALE_CAP = 130_000_000 * UNIT;
    uint256 public constant PLANNED_TOTAL_SUPPLY = 260_000_000 * UNIT;
    // Exclusive 29 Feb 2028 00:00 WIB. Last eligible: 28 Feb 23:59:59 WIB.
    uint256 public constant SALE_END = 1835370000;
    uint256 public immutable expectedChainId;
    address public immutable administrator;
    address payable public immutable treasury;
    IERC20 public immutable usdt;
    IVoinUsdFeed public immutable bnbUsdFeed;
    IVoinUsdFeed public immutable usdtUsdFeed;
    uint256 public immutable usdtScale;
    uint256 public immutable bnbMaxAge;
    uint256 public immutable usdtMaxAge;
    // Deployment parameters must be independently chosen from feed behavior
    // and accepted sale terms, not guessed from this draft.
    uint256 public immutable usdtMinimumUsd18;
    uint256 public immutable usdtMaximumUsd18;

    bool public paused = true;
    uint256 public totalAllocated;
    uint256 public totalBnbPaid;
    uint256 public totalUsdtPaid;
    mapping(address => uint256) public allocations;

    event Purchased(address indexed buyer, address indexed paymentAsset,
        uint256 tokenUnits, uint256 paymentAmount, uint256 usdCost18,
        uint256 totalAllocatedAfter);
    event PauseChanged(bool paused);
    event Withdrawn(address indexed paymentAsset, uint256 amount);

    modifier onlyAdministrator() {
        require(msg.sender == administrator, "Administrator only");
        _;
    }

    constructor(
        uint256 chainId_, address administrator_, address payable treasury_,
        address usdt_, address bnbUsdFeed_, address usdtUsdFeed_,
        uint256 bnbMaxAge_, uint256 usdtMaxAge_,
        uint256 usdtMinimumUsd18_, uint256 usdtMaximumUsd18_
    ) {
        require(chainId_ == 56 || chainId_ == 97, "Unsupported chain");
        require(block.chainid == chainId_, "Wrong chain");
        require(block.timestamp < SALE_END, "Deadline passed");
        require(administrator_ != address(0) && treasury_ != address(0), "Zero authority");
        require(usdt_.code.length > 0 && bnbUsdFeed_.code.length > 0
            && usdtUsdFeed_.code.length > 0, "Missing contract code");
        require(bnbMaxAge_ > 0 && usdtMaxAge_ > 0, "Invalid freshness policy");
        require(usdtMinimumUsd18_ > 0 && usdtMinimumUsd18_ < UNIT
            && usdtMaximumUsd18_ > UNIT, "Invalid USDT bounds");
        uint8 tokenDecimals = IERC20Metadata(usdt_).decimals();
        require(tokenDecimals <= 18, "Unsupported USDT precision");
        expectedChainId = chainId_;
        administrator = administrator_;
        treasury = treasury_;
        usdt = IERC20(usdt_);
        usdtScale = 10 ** uint256(tokenDecimals);
        bnbUsdFeed = IVoinUsdFeed(bnbUsdFeed_);
        usdtUsdFeed = IVoinUsdFeed(usdtUsdFeed_);
        bnbMaxAge = bnbMaxAge_;
        usdtMaxAge = usdtMaxAge_;
        usdtMinimumUsd18 = usdtMinimumUsd18_;
        usdtMaximumUsd18 = usdtMaximumUsd18_;
        // Paused by default. Deployment does NOT open the sale.
    }

    function currentBatch() public view returns (uint256) {
        return totalAllocated == PRESALE_CAP ? 10 : totalAllocated / BATCH_SIZE + 1;
    }

    function currentPriceUsdCents() external view returns (uint256) {
        return currentBatch();
    }

    function saleOpen() public view returns (bool) {
        return block.chainid == expectedChainId && !paused
            && block.timestamp < SALE_END && totalAllocated < PRESALE_CAP;
    }

    function quoteUsd(uint256 tokenUnits) public view returns (uint256 usdCost18) {
        require(tokenUnits > 0, "Zero allocation");
        require(tokenUnits <= PRESALE_CAP - totalAllocated, "Exceeds remaining cap");
        uint256 cursor = totalAllocated;
        uint256 left = tokenUnits;
        while (left > 0) {
            uint256 batch = cursor / BATCH_SIZE + 1;
            uint256 remaining = batch * BATCH_SIZE - cursor;
            uint256 take = left < remaining ? left : remaining;
            usdCost18 += Math.mulDiv(take, batch * 1e16, UNIT, Math.Rounding.Ceil);
            cursor += take;
            left -= take;
        }
    }

    function readPrice(IVoinUsdFeed feed, uint256 maxAge)
        private view returns (uint256 usdPrice18)
    {
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        require(answer > 0, "Nonpositive oracle price");
        require(updatedAt > 0 && updatedAt <= block.timestamp, "Invalid oracle timestamp");
        require(block.timestamp - updatedAt <= maxAge, "Stale oracle price");
        uint8 precision = feed.decimals();
        require(precision <= 18, "Unsupported feed precision");
        usdPrice18 = uint256(answer) * (10 ** uint256(18 - precision));
    }

    function quoteBnb(uint256 tokenUnits) public view returns (uint256 payment, uint256 usdCost18) {
        usdCost18 = quoteUsd(tokenUnits);
        uint256 price = readPrice(bnbUsdFeed, bnbMaxAge);
        payment = Math.mulDiv(usdCost18, UNIT, price, Math.Rounding.Ceil);
    }

    function quoteUsdt(uint256 tokenUnits) public view returns (uint256 payment, uint256 usdCost18) {
        usdCost18 = quoteUsd(tokenUnits);
        uint256 price = readPrice(usdtUsdFeed, usdtMaxAge);
        require(price >= usdtMinimumUsd18 && price <= usdtMaximumUsd18, "USDT outside bounds");
        payment = Math.mulDiv(usdCost18, usdtScale, price, Math.Rounding.Ceil);
    }

    // maxPayment and quoteDeadline protect the buyer against a changed quote.
    // Purchases are for msg.sender only. No arbitrary buyer attribution.
    function buyWithBnb(uint256 tokenUnits, uint256 maxPayment, uint256 quoteDeadline)
        external payable nonReentrant
    {
        require(saleOpen(), "Sale closed or paused");
        require(block.timestamp <= quoteDeadline, "Quote expired");
        (uint256 requiredAmount, uint256 usdCost18) = quoteBnb(tokenUnits);
        require(requiredAmount <= maxPayment, "Payment exceeds buyer limit");
        require(msg.value >= requiredAmount, "Insufficient BNB");
        allocations[msg.sender] += tokenUnits;
        totalAllocated += tokenUnits;
        totalBnbPaid += requiredAmount;
        emit Purchased(msg.sender, address(0), tokenUnits, requiredAmount, usdCost18, totalAllocated);
        uint256 refund = msg.value - requiredAmount;
        if (refund > 0) {
            (bool ok, ) = payable(msg.sender).call{value: refund}("");
            require(ok, "Excess BNB refund failed");
        }
    }

    // Investor approves THIS contract for the quoted USDT amount first.
    function buyWithUsdt(uint256 tokenUnits, uint256 maxPayment, uint256 quoteDeadline)
        external nonReentrant
    {
        require(saleOpen(), "Sale closed or paused");
        require(block.timestamp <= quoteDeadline, "Quote expired");
        (uint256 requiredAmount, uint256 usdCost18) = quoteUsdt(tokenUnits);
        require(requiredAmount <= maxPayment, "Payment exceeds buyer limit");
        uint256 beforeBalance = usdt.balanceOf(address(this));
        allocations[msg.sender] += tokenUnits;
        totalAllocated += tokenUnits;
        totalUsdtPaid += requiredAmount;
        usdt.safeTransferFrom(msg.sender, address(this), requiredAmount);
        require(usdt.balanceOf(address(this)) - beforeBalance == requiredAmount,
            "USDT amount received differs");
        emit Purchased(msg.sender, address(usdt), tokenUnits, requiredAmount, usdCost18, totalAllocated);
    }

    function setPaused(bool value) external onlyAdministrator {
        if (!value) {
            require(block.chainid == expectedChainId && block.timestamp < SALE_END, "Cannot open");
            readPrice(bnbUsdFeed, bnbMaxAge);
            uint256 price = readPrice(usdtUsdFeed, usdtMaxAge);
            require(price >= usdtMinimumUsd18 && price <= usdtMaximumUsd18, "USDT outside bounds");
        }
        paused = value;
        emit PauseChanged(value);
    }

    // DRAFT custody policy: funds held by contract, administrator can withdraw
    // only to immutable treasury. No user cancellation/refund mechanism.
    // Final policy/legal terms MUST be resolved before launch.
    function withdrawBnb(uint256 amount) external onlyAdministrator nonReentrant {
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");
        (bool ok, ) = treasury.call{value: amount}("");
        require(ok, "BNB withdrawal failed");
        emit Withdrawn(address(0), amount);
    }

    function withdrawUsdt(uint256 amount) external onlyAdministrator nonReentrant {
        require(amount > 0 && amount <= usdt.balanceOf(address(this)), "Invalid amount");
        usdt.safeTransfer(treasury, amount);
        emit Withdrawn(address(usdt), amount);
    }

    receive() external payable { revert("Use buyWithBnb"); }
    fallback() external payable { revert("Unknown function"); }
}
