// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

struct Bytes32Set {
    bytes32[] items;
    mapping(bytes32 => bool) saved;
}

library LibBytes32Set {
    function add(Bytes32Set storage s, bytes32 item) internal {
        if (!s.saved[item]) {
            s.items.push(item);
            s.saved[item] = true;
        }
    }

    function contains(Bytes32Set storage s, bytes32 item) internal view returns (bool) {
        return s.saved[item];
    }

    function count(Bytes32Set storage s) internal view returns (uint256) {
        return s.items.length;
    }

    function rand(Bytes32Set storage s, uint256 seed) internal view returns (bytes32) {
        if (s.items.length > 0) {
            return s.items[seed % s.items.length];
        } else {
            return bytes32(0);
        }
    }

    function forEach(Bytes32Set storage s, function(bytes32) external func) internal {
        for (uint256 i; i < s.items.length; ++i) {
            func(s.items[i]);
        }
    }

    function reduce(Bytes32Set storage s, uint256 acc, function(uint256, bytes32) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.items.length; ++i) {
            acc = func(acc, s.items[i]);
        }
        return acc;
    }
}
