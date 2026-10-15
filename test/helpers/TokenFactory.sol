// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VerdictIMD} from "../../src/VerdictIMD.sol";

/// @dev Test fixture only: holds and moves tokens as the launch factory would.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (VerdictIMD) {
        return new VerdictIMD{salt: salt}();
    }

    function move(VerdictIMD token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @dev A transfer must succeed without invoking recipient code.
contract RejectingReceiver {
    fallback() external {
        revert("recipient callback must not be called");
    }
}
