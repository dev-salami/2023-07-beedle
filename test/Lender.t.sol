// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Lender.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";

contract TERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Test ERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "TERC20";
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

contract LenderTest is Test {
    Lender public lender;

    TERC20 public loanToken;
    TERC20 public collateralToken;

    address public lender1 = address(0x1);
    address public lender2 = address(0x2);
    address public borrower = address(0x3);
    address public fees = address(0x4);

    function setUp() public {
        lender = new Lender();
        loanToken = new TERC20();
        collateralToken = new TERC20();
        loanToken.mint(address(lender1), 100000 * 10 ** 18);
        loanToken.mint(address(lender2), 100000 * 10 ** 18);
        collateralToken.mint(address(borrower), 100000 * 10 ** 18);
        vm.startPrank(lender1);
        loanToken.approve(address(lender), 1000000 * 10 ** 18);
        collateralToken.approve(address(lender), 1000000 * 10 ** 18);
        vm.startPrank(lender2);
        loanToken.approve(address(lender), 1000000 * 10 ** 18);
        collateralToken.approve(address(lender), 1000000 * 10 ** 18);
        vm.startPrank(borrower);
        loanToken.approve(address(lender), 1000000 * 10 ** 18);
        collateralToken.approve(address(lender), 1000000 * 10 ** 18);
    }

    function test_createPool() public {
        vm.startPrank(lender1);
        Pool memory p = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        lender.setPool(p);
        // PT
        assertEq(loanToken.balanceOf(address(lender)), 1000 * 10 ** 18);
    }

    function test_borrow() public {
        vm.startPrank(lender1);
        Pool memory p = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        (,,,, uint256 poolBalance,,,,) = lender.pools(poolId);
        assertEq(poolBalance, 1000 * 10 ** 18);

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolId, debt: 100 * 10 ** 18, collateral: 100 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;
        lender.borrow(borrows);

        assertEq(loanToken.balanceOf(address(borrower)), 995 * 10 ** 17);
        assertEq(collateralToken.balanceOf(address(lender)), 100 * 10 ** 18);
        /// PT: check if fee receiver gets fee
        assertEq(loanToken.balanceOf(lender.owner()), 5 * 10 ** 17);

        (,,,, poolBalance,,,,) = lender.pools(poolId);
        assertEq(poolBalance, 900 * 10 ** 18);
    }

    function test_repay() public {
        test_borrow();
        vm.warp(block.timestamp + 1 days);
        // protocol fee after 1 day
        uint256 feeAfterAday = 2739726027397260;
        uint256 interestAfterAday = 24657534246575342;

        bytes32 poolId = keccak256(abi.encode(address(lender1), address(loanToken), address(collateralToken)));

        vm.startPrank(borrower);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;
        // borrower now has 0.6 eth + 99.5 eth borrowed = 100.1 eth
        // before repaying
        loanToken.mint(address(borrower), 6 * 10 ** 17);
        // PT: check for total amount of loan token borrower has
        uint256 balanceBeforeDeptPayment = 1001 * 10 ** 17;
        assertEq(loanToken.balanceOf(address(borrower)), balanceBeforeDeptPayment);

        lender.repay(loanIds);
        // PT: check current balance of fee receiver
        assertEq(loanToken.balanceOf(lender.owner()), 5e17 + feeAfterAday);
        //PT : check balance after payment. note dept is 100 ether
        assertEq(
            loanToken.balanceOf(address(borrower)),
            balanceBeforeDeptPayment - 100 ether - feeAfterAday - interestAfterAday
        );
        // PT : check to enssure lender get their interest
        assertEq(collateralToken.balanceOf(address(lender)), 0);
        (,,,, uint256 poolBalance,,,,) = lender.pools(poolId);
        assertEq(poolBalance, 1000 * 10 ** 18 + interestAfterAday);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         AUCTIONS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_startAuction() public {
        test_borrow();

        vm.startPrank(lender1);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        lender.startAuction(loanIds);

        (,,,,,,,, uint256 startTime,) = lender.loans(0);

        assertEq(startTime, block.timestamp);
    }

    function test_buyLoan() public {
        test_borrow();
        // accrue interest
        vm.warp(block.timestamp + 364 days + 12 hours);
        // kick off auction
        vm.startPrank(lender1);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        lender.startAuction(loanIds);

        vm.startPrank(lender2);
        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        // warp to middle of auction
        vm.warp(block.timestamp + 12 hours);

        lender.buyLoan(0, poolId);

        // assert that we paid the interest and new loan is in our name
        assertEq(lender.getLoanDebt(0), 110 * 10 ** 18);
    }

    function test_seize() public {
        test_startAuction();

        vm.warp(block.timestamp + 2 days);

        vm.startPrank(lender2);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        lender.seizeLoan(loanIds);

        // assertEq(collateralToken.balanceOf(address(lender2)), 100*10**18);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         REFINANCE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_giveLoan() public {
        test_borrow();

        vm.startPrank(lender2);
        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        lender.setPool(p);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = keccak256(abi.encode(address(lender2), address(loanToken), address(collateralToken)));

        vm.startPrank(lender1);
        lender.giveLoan(loanIds, poolIds);

        (,,,, uint256 poolBalance,,,,) = lender.pools(poolIds[0]);
        assertEq(poolBalance, 900 * 10 ** 18);
        bytes32 poolId = keccak256(abi.encode(address(lender1), address(loanToken), address(collateralToken)));
        (,,,, poolBalance,,,,) = lender.pools(poolId);
        assertEq(poolBalance, 1000 * 10 ** 18);
    }

    function test_refinance() public {
        test_borrow();

        vm.startPrank(lender2);
        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        lender.setPool(p);

        vm.startPrank(borrower);
        Refinance memory r = Refinance({
            loanId: 0,
            poolId: keccak256(abi.encode(address(lender2), address(loanToken), address(collateralToken))),
            debt: 100 * 10 ** 18,
            collateral: 100 * 10 ** 18
        });
        Refinance[] memory rs = new Refinance[](1);
        rs[0] = r;

        lender.refinance(rs);

        // assertEq(loanToken.balanceOf(address(borrower)), 100*10**18);
        // assertEq(collateralToken.balanceOf(address(lender)), 100*10**18);
    }

    function test_interest() public {
        test_borrow();

        vm.warp(block.timestamp + 365 days);

        uint256 debt = lender.getLoanDebt(0);

        assertEq(debt, 110 * 10 ** 18);
    }

    function test_RevertWhen_StartAuction() public {
        test_borrow();

        vm.startPrank(lender2);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        // Expect revert when non-owner tries to auction a loan
        vm.expectRevert();
        lender.startAuction(loanIds);
    }

    function test_RevertWhen_BorrowTooSmall() public {
        vm.startPrank(lender1);
        Pool memory p = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolId, debt: 99 * 10 ** 18, collateral: 100 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;

        // Expect revert when loan size is smaller than the minimum
        vm.expectRevert("Debt smaller than minimum loan size");
        lender.borrow(borrows);
    }

    function test_RevertWhen_BorrowTooLarge() public {
        vm.startPrank(lender1);
        Pool memory p = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolId, debt: 10000 * 10 ** 18, collateral: 10000 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;

        // Expect revert when loan amount exceeds pool balance
        vm.expectRevert("Pool lacks funds");
        lender.borrow(borrows);
    }

    function test_RevertWhen_RepayNoTokens() public {
        test_borrow();

        vm.startPrank(borrower);

        loanToken.transfer(address(0), 100 * 10 ** 18);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        // Expect revert when attempting to repay with insufficient token balance
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        lender.repay(loanIds);
    }

    function test_RevertWhen_BuyLoanTooLate() public {
        test_startAuction();

        vm.startPrank(lender2);
        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        vm.warp(block.timestamp + 2 days);

        // Expect revert when trying to buy loan after auction ended
        vm.expectRevert("Auction ended");
        lender.buyLoan(0, poolId);
    }

    function test_RevertWhen_BuyLoanRateTooHigh() public {
        test_startAuction();

        vm.startPrank(lender2);
        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 100000,
            outstandingLoans: 0
        });
        bytes32 poolId = lender.setPool(p);

        vm.warp(block.timestamp + 12 hours);

        // Expect revert when interest rate is too high
        vm.expectRevert("Interest rate too high");
        lender.buyLoan(0, poolId);
    }

    function test_RevertWhen_SeizeTooEarly() public {
        test_startAuction();

        vm.startPrank(lender2);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        // Expect revert when trying to seize loan before auction ends
        vm.expectRevert("Auction not ended");
        lender.seizeLoan(loanIds);
    }
}
