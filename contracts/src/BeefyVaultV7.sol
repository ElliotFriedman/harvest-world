// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IAllowanceTransfer} from "@permit2/interfaces/IAllowanceTransfer.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {IAgentBook} from "./interfaces/IAgentBook.sol";

import {IStrategyV7} from "./interfaces/IStrategyV7.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract BeefyVaultV7 is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // The strategy currently in use by the vault.
    IStrategyV7 public strategy;

    // Permit2 for token transfers (World App pre-approves all tokens to this contract)
    IAllowanceTransfer public constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // World ID on-chain verification (WorldIDRouter on World Chain mainnet)
    IWorldID public constant WORLD_ID_ROUTER = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
    uint256 public constant GROUP_ID = 1; // Orb credentials only

    // AgentBook registry — maps human-backed agent wallets → humanId (nullifierHash)
    // Agents register via: npx @worldcoin/agentkit-cli register <wallet>
    IAgentBook public constant AGENT_BOOK = IAgentBook(0xA23aB2712eA7BBa896930544C7d6636a96b944dA);

    // Derived from app_id + action, set in initialize()
    uint256 public externalNullifierHash;

    // Sybil resistance: each nullifier can only be used once
    mapping(uint256 => bool) public nullifierHashes;

    // Verified humans (World ID) and human-backed agents (AgentKit)
    mapping(address => bool) public verifiedHumans;

    event HumanVerification(address indexed user, bool verified);

    error InvalidNullifier();

    modifier onlyHuman() {
        _onlyHuman();
        _;
    }

    function _onlyHuman() private view {
        require(
            verifiedHumans[msg.sender] || AGENT_BOOK.lookupHuman(msg.sender) != 0,
            "Harvest: humans only"
        );
    }

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'moo' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _strategy the address of the strategy.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     */
    function initialize(
        IStrategyV7 _strategy,
        string memory _name,
        string memory _symbol,
        uint256 _externalNullifierHash
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __ReentrancyGuard_init();
        strategy = _strategy;
        externalNullifierHash = _externalNullifierHash;
    }

    function want() public view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(strategy.want());
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint256) {
        return want().balanceOf(address(this)) + IStrategyV7(strategy).balanceOf();
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance() * 1e18 / totalSupply();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external onlyHuman {
        deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     * Pulls tokens via Permit2 allowance-based transferFrom.
     * User must have approved this vault as a Permit2 spender beforehand.
     */
    function deposit(uint256 _amount) public onlyHuman nonReentrant {
        strategy.beforeDeposit();

        uint256 _pool = balance();
        // casting to 'uint160' is safe because deposit amounts are bounded by real token supplies (< 2^160)
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.transferFrom(msg.sender, address(this), uint160(_amount), address(want()));

        uint256 shares = totalSupply() == 0 ? _amount : (_amount * totalSupply()) / _pool;
        _mint(msg.sender, shares);
        earn();
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint256 _bal = available();
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint256 b = want().balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r - b;
            strategy.withdraw(_withdraw);
            uint256 _after = want().balanceOf(address(this));
            uint256 _diff = _after - b;
            if (_diff < _withdraw) {
                r = b + _diff;
            }
        }

        want().safeTransfer(msg.sender, r);
    }

    /**
     * @dev Verify a human via World ID on-chain proof. Trustless — no backend needed.
     * User calls this once with their IDKit proof, then can deposit freely.
     * Signal is msg.sender, so the proof is bound to the caller's address.
     */
    function verifyHuman(uint256 root, uint256 nullifierHash, uint256[8] calldata proof) external {
        if (nullifierHashes[nullifierHash]) revert InvalidNullifier();

        WORLD_ID_ROUTER.verifyProof(
            root, GROUP_ID, _hashToField(abi.encodePacked(msg.sender)), nullifierHash, externalNullifierHash, proof
        );

        nullifierHashes[nullifierHash] = true;
        verifiedHumans[msg.sender] = true;
        emit HumanVerification(msg.sender, true);
    }

    /**
     * @dev Direct strategy setter. No timelock for hackathon.
     */
    function setStrategy(IStrategyV7 _strategy) external onlyOwner {
        require(address(_strategy) != address(0), "!strategy");
        require(_strategy.want() == want(), "!want");
        if (address(strategy) != address(0)) {
            strategy.retireStrat();
        }
        strategy = _strategy;
        earn();
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Hash a value to a field element for World ID proof verification.
     * Matches the ByteHasher.hashToField() from World ID contracts.
     */
    function _hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
