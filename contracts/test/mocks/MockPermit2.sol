// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Minimal Permit2 mock implementing only the allowance-based API the vault uses.
///      Deploy at 0x000000000022D473030F116dDEE9F6B43aC78BA3 via vm.etch.
contract MockPermit2 {
    using SafeERC20 for IERC20;

    // owner => token => spender => (amount, expiration)
    mapping(address => mapping(address => mapping(address => uint160))) public allowances;

    event Approval(
        address indexed owner, address indexed token, address indexed spender, uint160 amount, uint48 expiration
    );

    /// @notice Set spending allowance (called by the token owner directly).
    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 /*expiration*/
    )
        external
    {
        allowances[msg.sender][token][spender] = amount;
        emit Approval(msg.sender, token, spender, amount, 0);
    }

    /// @notice Transfer tokens from `from` to `to` (called by the vault).
    function transferFrom(address from, address to, uint160 amount, address token) external {
        uint160 allowed = allowances[from][token][msg.sender];
        require(allowed >= amount, "MockPermit2: insufficient allowance");
        allowances[from][token][msg.sender] = allowed - amount;
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
