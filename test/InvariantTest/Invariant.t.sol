// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {TERC20} from "../Lender.t.sol";
import {Lender} from "../../src/Lender.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    Lender lender;
    TERC20 public loanToken;
    TERC20 public collateralToken;
    uint256 public startingAmount;
    // address public lender1 = address(0x1);
    // address public lender2 = address(0x2);
    // address public borrower = address(0x3);

    Handler handler;

    function setUp() public {
        lender = new Lender();
        loanToken = new TERC20();
        collateralToken = new TERC20();

        handler = new Handler(lender, loanToken, collateralToken);
        vm.stopPrank();

        bytes4[] memory selectors = new bytes4[](2);
        // selectors[0] = handler.borrowLoan.selector;
        selectors[1] = handler.createPool.selector;

        // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function statefulFuzz_testInvariantHandler() public {
        assert(loanToken.balanceOf(address(lender)) + handler.ghost_totalLoan() == handler.ghost_totalPoolDeposit());
    }
}
