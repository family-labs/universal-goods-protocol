// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ILSP7DigitalAsset} from
    "@lukso/lsp7-contracts/contracts/ILSP7DigitalAsset.sol";

/// @title DataLinkedEscrow
/// @notice Minimal escrow that links a token deposit to a keccak256 hash of off-chain payload data.
///         The depositor can later settle the escrow, releasing tokens to the payee.
///         The payloadHash itself is the escrow key, giving both parties a deterministic
///         way to query escrow state from the off-chain message alone.
contract DataLinkedEscrow {
    struct Escrow {
        address depositor;
        address payee;
        address token;
        uint256 amount;
        bool settled;
    }

    mapping(bytes32 => Escrow) public escrows;

    event EscrowCreated(
        bytes32 indexed payloadHash,
        address indexed depositor,
        address indexed payee,
        address token,
        uint256 amount
    );

    event EscrowSettled(bytes32 indexed payloadHash);

    error EscrowNotFound();
    error EscrowAlreadyExists();
    error EscrowAlreadySettled();
    error OnlyDepositor();

    /// @notice Deposit tokens into escrow, keyed by the payload hash.
    /// @dev Caller must have authorised this contract as an operator on the LSP7 token first.
    ///      Each payloadHash can only be used once — one invoice, one escrow.
    /// @param token  LSP7 token address.
    /// @param amount Amount of tokens to escrow.
    /// @param payee  Address that will receive the tokens on settlement.
    /// @param payloadHash  keccak256 hash of the off-chain credential/invoice data.
    function deposit(address token, uint256 amount, address payee, bytes32 payloadHash)
        external
    {
        if (escrows[payloadHash].depositor != address(0)) revert EscrowAlreadyExists();

        escrows[payloadHash] = Escrow({
            depositor: msg.sender,
            payee: payee,
            token: token,
            amount: amount,
            settled: false
        });

        // Pull tokens from depositor into this contract
        ILSP7DigitalAsset(token).transfer(msg.sender, address(this), amount, true, "");

        emit EscrowCreated(payloadHash, msg.sender, payee, token, amount);
    }

    /// @notice Settle the escrow, releasing tokens to the payee.
    /// @dev Only the original depositor can settle.
    /// @param payloadHash The payload hash identifying the escrow to settle.
    function settle(bytes32 payloadHash) external {
        Escrow storage e = escrows[payloadHash];
        if (e.depositor == address(0)) revert EscrowNotFound();
        if (e.settled) revert EscrowAlreadySettled();
        if (msg.sender != e.depositor) revert OnlyDepositor();

        e.settled = true;

        // Release tokens to payee
        ILSP7DigitalAsset(e.token).transfer(address(this), e.payee, e.amount, true, "");

        emit EscrowSettled(payloadHash);
    }
}
