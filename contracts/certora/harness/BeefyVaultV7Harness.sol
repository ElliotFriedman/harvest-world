// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// ---------------------------------------------------------------------------
// BeefyVaultV7Harness — fully self-contained vault model for Certora
//
// No OZ dependencies. Implements ERC20 share tokens inline.
// All arithmetic is unchecked to prevent spurious overflow reverts.
// ---------------------------------------------------------------------------
contract BeefyVaultV7Harness {

    // ---- ERC20 share token state --------------------------------------------
    mapping(address => uint256) internal _shareBalances;
    uint256 internal _shareTotalSupply;

    // ---- Vault accounting ---------------------------------------------------
    uint256 public hVaultBal;
    uint256 public hStratBal;
    mapping(address => uint256) public hUserBal;
    address public hStrategy;
    address public hOwner;

    // ---- ERC20 interface (minimal) ------------------------------------------

    function totalSupply() public view returns (uint256) {
        return _shareTotalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _shareBalances[account];
    }

    function _mint(address to, uint256 amount) internal {
        unchecked {
            _shareBalances[to] += amount;
            _shareTotalSupply += amount;
        }
    }

    function _burn(address from, uint256 amount) internal {
        unchecked {
            _shareBalances[from] -= amount;
            _shareTotalSupply -= amount;
        }
    }

    // ---- Core vault functions -----------------------------------------------

    function balance() public view returns (uint256) {
        unchecked { return hVaultBal + hStratBal; }
    }

    function available() public view returns (uint256) {
        return hVaultBal;
    }

    function getPricePerFullShare() public view returns (uint256) {
        if (_shareTotalSupply == 0) return 1e18;
        unchecked { return (hVaultBal + hStratBal) * 1e18 / _shareTotalSupply; }
    }

    function deposit(uint256 _amount) public {
        uint256 _pool;
        unchecked { _pool = hVaultBal + hStratBal; }

        unchecked {
            hUserBal[msg.sender] -= _amount;
            hVaultBal += _amount;
        }

        uint256 shares;
        if (_shareTotalSupply == 0) {
            shares = _amount;
        } else {
            unchecked { shares = (_amount * _shareTotalSupply) / _pool; }
        }
        _mint(msg.sender, shares);

        // earn: vault -> strategy
        unchecked { hStratBal += hVaultBal; }
        hVaultBal = 0;
    }

    function depositAll() external {
        deposit(hUserBal[msg.sender]);
    }

    function earn() public {
        unchecked { hStratBal += hVaultBal; }
        hVaultBal = 0;
    }

    function withdraw(uint256 _shares) public {
        uint256 r;
        unchecked { r = ((hVaultBal + hStratBal) * _shares) / _shareTotalSupply; }
        _burn(msg.sender, _shares);

        uint256 b = hVaultBal;
        if (b < r) {
            unchecked {
                uint256 _withdraw = r - b;
                uint256 toReturn = _withdraw <= hStratBal ? _withdraw : hStratBal;
                hStratBal -= toReturn;
                hVaultBal += toReturn;
                if (toReturn < _withdraw) {
                    r = hVaultBal;
                }
            }
        }

        unchecked {
            hVaultBal -= r;
            hUserBal[msg.sender] += r;
        }
    }

    function withdrawAll() external {
        withdraw(_shareBalances[msg.sender]);
    }

    // ---- Access control -----------------------------------------------------

    function setStrategy(address _strategy) external {
        require(msg.sender == hOwner, "!owner");
        require(_strategy != address(0), "!strategy");
        hStrategy = _strategy;
        earn();
    }

    function inCaseTokensGetStuck(address _token) external {
        require(msg.sender == hOwner, "!owner");
        require(_token != address(0), "!token");
    }

    // ---- View helpers -------------------------------------------------------

    function vaultTokenBalance() external view returns (uint256) { return hVaultBal; }
    function strategyTokenBalance() external view returns (uint256) { return hStratBal; }
    function currentOwner() external view returns (address) { return hOwner; }
    function wantBalanceOf(address user) external view returns (uint256) { return hUserBal[user]; }
    function strategyAddress() external view returns (address) { return hStrategy; }

    function addYield(uint256 _amount) external {
        unchecked { hStratBal += _amount; }
    }
}
