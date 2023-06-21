// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

// OpenZeppelin dependencies
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

// Aragon dependencies
import "@aragon/os/contracts/apps/AragonApp.sol";

/**
 * @title VAULTDAO
 */
contract VAULTDAO is AragonApp, ReentrancyGuard {
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant RELEASE_ROLE = keccak256("RELEASE_ROLE");

    // AragonApp public identifiers for events & state
    string private constant ERROR_INVALID_INIT_PARAMS = "INVALID_INIT_PARAMS";
    string private constant ERROR_INVALID_BENEFICIARY = "INVALID_BENEFICIARY";
    string private constant ERROR_INVALID_TOKEN = "INVALID_TOKEN";
    string private constant ERROR_TOKEN_TRANSFER_FAILED = "TOKEN_TRANSFER_FAILED";
    string private constant ERROR_INVALID_TOKEN_CONTROLLER = "INVALID_TOKEN_CONTROLLER";
    string private constant ERROR_NOT_ENOUGH_BALANCE = "NOT_ENOUGH_BALANCE";
    string private constant ERROR_CAN_NOT_RELEASE = "CAN_NOT_RELEASE";
    string private constant ERROR_VESTING_ALREADY_REVOKED = "VESTING_ALREADY_REVOKED";

    struct Vesting {
        uint256 amount;
        uint64 start;
        uint64 vesting;
        bool revokable;
        bool revoked;
    }

    ERC20 public token;
    mapping (address => Vesting) public vestings;

    /**
     * @notice Initialize the vesting contract.
     * @param _token Address of the token to be vested
     * @param _beneficiary Address of the beneficiary
     * @param _start Date in seconds of the beginning of the vesting period
     * @param _cliffSec Duration in seconds of the cliff
     * @param _durationSec Duration in seconds of the vesting period
     * @param _revokable Whether the vesting is revokable or not
     */
    function initialize(
        ERC20 _token,
        address _beneficiary,
        uint64 _start,
        uint64 _cliffSec,
        uint64 _durationSec,
        bool _revokable
    ) public onlyInit {
        initialized();

        require(_beneficiary != address(0), ERROR_INVALID_BENEFICIARY);
        require(_token != address(0), ERROR_INVALID_TOKEN);

        // We already checked the token and beneficiary so we just need to check vesting times
        require(_start + _cliffSec <= _start + _durationSec, ERROR_INVALID_INIT_PARAMS);

        token = _token;
        vestings[_beneficiary] = Vesting({amount: 0, start: _start, vesting: uint64(_start + _durationSec), revokable: _revokable, revoked: false});
    }

    /**
     * @notice Create a new vesting agreement
     * @param _receiver The address that will receive the vested tokens
     * @param _amount The amount of tokens to be vested
     */
    function assignVested(address _receiver, uint256 _amount) authP(WITHDRAWER_ROLE) public {
        require(_amount > 0, ERROR_INVALID_INIT_PARAMS);
        require(token.transferFrom(msg.sender, address(this), _amount), ERROR_TOKEN_TRANSFER_FAILED);

        vestings[_receiver].amount += _amount;
    }

    /**
     * @notice Withdraw vested tokens
     */
    function release() authP(RELEASE_ROLE) public nonReentrant {
        uint256 unreleased = _releasableAmount(msg.sender);

        require(unreleased > 0, ERROR_CAN_NOT_RELEASE);

        vestings[msg.sender].amount = vestings[msg.sender].amount - unreleased;
        require(token.transfer(msg.sender, unreleased), ERROR_TOKEN_TRANSFER_FAILED);
    }

    /**
     * @notice Revoke all vesting. Tokens already vested remain vested.
     */
    function revoke() public {
        Vesting storage vesting = vestings[msg.sender];

        require(vesting.revokable, ERROR_VESTING_ALREADY_REVOKED);
        require(!vesting.revoked, ERROR_VESTING_ALREADY_REVOKED);

        uint256 balance = token.balanceOf(address(this));
        uint256 unreleased = _releasableAmount(msg.sender);

        uint256 refund = balance - unreleased;

        vesting.revoked = true;
        vesting.amount = unreleased;

        require(token.transfer(msg.sender, refund), ERROR_TOKEN_TRANSFER_FAILED);
    }

    /**
     * @notice Check the amount of tokens that can be released
     * @param _beneficiary Address of the beneficiary
     * @return The amount of tokens that can be released
     */
    function releasableAmount(address _beneficiary) public view isInitialized returns (uint256) {
        return _releasableAmount(_beneficiary);
    }

    /**
     * @dev Calculate the amount of vested tokens that can be released
     * @param _beneficiary Address of the beneficiary
     * @return The amount of tokens that can be released
     */
    function _releasableAmount(address _beneficiary) internal view returns (uint256) {
        Vesting storage vesting = vestings[_beneficiary];

        if (block.timestamp < vesting.start) {
            return 0;
        } else if (block.timestamp >= vesting.vesting || vesting.revoked) {
            return vesting.amount;
        } else {
            return vesting.amount * (block.timestamp - vesting.start) / (vesting.vesting - vesting.start);
        }
    }
}
