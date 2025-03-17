// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {AddressSet, LibAddressSet} from "../helpers/AddressSet.sol";
import {Bytes32Set, LibBytes32Set} from "../helpers/Bytes32Set.sol";

import {TERC20} from "../Lender.t.sol";
import "../../src/Lender.sol";

contract Handler is Test {
    using LibAddressSet for AddressSet;
    using LibBytes32Set for Bytes32Set;

    uint256 constant STARTER_BALANCE = 100000 * 10 ** 18;
    Lender public lender;
    TERC20 public loanToken;
    TERC20 public collateralToken;
    address public lender1 = address(0x1);
    address public lender2 = address(0x2);
    address public borrower = address(0x3);

    //// ACTORS //////
    AddressSet internal _actors;
    address internal currentActor;

    AddressSet internal _borrowers;
    address internal currentBorrower;

    modifier createActor() {
        currentActor = msg.sender;
        vm.startPrank(msg.sender);
        loanToken.mint(address(msg.sender), STARTER_BALANCE);
        loanToken.approve(address(lender), type(uint256).max);

        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier createBorrower() {
        currentBorrower = msg.sender;
        vm.startPrank(msg.sender);
        collateralToken.mint(address(msg.sender), STARTER_BALANCE);
        collateralToken.approve(address(lender), type(uint256).max);

        _borrowers.add(msg.sender);
        _;
    }

    modifier useBorrower(uint256 actorIndexSeed) {
        currentBorrower = _borrowers.rand(actorIndexSeed);
        _;
    }
    /////////////////

    uint256 public ghost_totalPoolDeposit;
    uint256 public ghost_totalLoan;

    Bytes32Set internal _ghost_validPoolIds;

    constructor(Lender _lender, TERC20 _loanToken, TERC20 _collateralToken) {
        loanToken = _loanToken;
        collateralToken = _collateralToken;
        lender = _lender;
    }

    function createPool(uint256 depositAmt) public createActor {
        depositAmt = bound(depositAmt, 1 ether, loanToken.balanceOf(currentActor));
        vm.startPrank(currentActor);
        uint256 prevBalance = loanToken.balanceOf(currentActor);
        bytes32 xPoolId = lender.getPoolId(currentActor, address(loanToken), address(collateralToken));
        (,,,,,,,, uint256 expectedOutstandingLoans) = lender.pools(xPoolId);
        console.log(expectedOutstandingLoans);
        Pool memory p = Pool({
            lender: currentActor,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: depositAmt,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: expectedOutstandingLoans
        });

        bytes32 poolId = lender.setPool(p);
        _ghost_validPoolIds.add(poolId);
        uint256 newBalance = loanToken.balanceOf(currentActor);
        // console.log("Prev", prevBalance);
        // console.log("New", newBalance);
        uint256 balanceChange;
        if (newBalance == prevBalance) {
            return;
        } else if (newBalance > prevBalance) {
            balanceChange = newBalance - prevBalance;
            // console.log(balanceChange);
            ghost_totalPoolDeposit -= balanceChange;
        } else {
            balanceChange = prevBalance - newBalance;
            // console.log(balanceChange);
            ghost_totalPoolDeposit += balanceChange;
        }

        // ghost_totalPoolDeposit += newBalance -;
    }

    function borrowLoan(uint256 toSeed, uint256 _borrowAmt) public createBorrower {
        bytes32 randomPool = _ghost_validPoolIds.rand(toSeed);
        (,,, uint256 minLoanSize, uint256 poolBalance,,,,) = lender.pools(randomPool);

        if (
            _ghost_validPoolIds.count() == 0 || minLoanSize > poolBalance
                || minLoanSize > loanToken.balanceOf(currentBorrower) || loanToken.balanceOf(currentBorrower) > poolBalance
        ) {
            return;
        }

        // if (_borrowAmt > poolBalance) {
        //     return;
        // }
        // vm.assume(condition);

        // _borrowAmt = bound(_borrowAmt, minLoanSize, poolBalance);
        _borrowAmt = bound(_borrowAmt, minLoanSize, loanToken.balanceOf(currentBorrower));

        vm.startPrank(currentBorrower);
        console.log("Pool COunt", _ghost_validPoolIds.count());
        Borrow memory b = Borrow({poolId: randomPool, debt: _borrowAmt, collateral: _borrowAmt});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;
        lender.borrow(borrows);
        ghost_totalLoan += _borrowAmt;
    }
}
