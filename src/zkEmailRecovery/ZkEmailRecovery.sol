// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PackedUserOperation} from "modulekit/external/ERC4337.sol";
import {EmailAccountRecovery} from "ether-email-auth/packages/contracts/src/EmailAccountRecovery.sol";

import {GuardianManager} from "./GuardianManager.sol";
import {RouterManager} from "./RouterManager.sol";
import {IZkEmailRecovery} from "../interfaces/IZkEmailRecovery.sol";

interface IRecoveryModule {
    function recover(bytes calldata data) external;
}

contract ZkEmailRecovery is
    GuardianManager,
    RouterManager,
    EmailAccountRecovery,
    IZkEmailRecovery
{
    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /** Mapping of account address to recovery delay */
    mapping(address => uint256) public recoveryDelays;

    /** Mapping of account address to recovery request */
    mapping(address => RecoveryRequest) public recoveryRequests;

    constructor(
        address _verifier,
        address _dkimRegistry,
        address _emailAuthImpl
    ) {
        verifierAddr = _verifier;
        dkimAddr = _dkimRegistry;
        emailAuthImplementationAddr = _emailAuthImpl;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     * @param guardianData The guardian data to setup the guardian manager with
     */
    function configureRecovery(
        bytes calldata guardianData,
        uint256 recoveryDelay
    ) external {
        address account = msg.sender;

        setupGuardians(account, guardianData);

        if (recoveryRequests[account].executeAfter > 0) {
            revert RecoveryAlreadyInitiated();
        }

        address router = deployRouterForAccount(account);

        recoveryDelays[account] = recoveryDelay;

        emit RecoveryConfigured(account, recoveryDelay, router);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     MODULE LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IZkEmailRecovery
    function getRecoveryDelay(address account) external view returns (uint256) {
        return recoveryDelays[account];
    }

    /// @inheritdoc IZkEmailRecovery
    function getRecoveryRequest(
        address account
    ) external view returns (RecoveryRequest memory) {
        return recoveryRequests[account];
    }

    /// @inheritdoc EmailAccountRecovery
    function acceptanceSubjectTemplates()
        public
        pure
        override
        returns (string[][] memory)
    {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](5);
        templates[0][0] = "Accept";
        templates[0][1] = "guardian";
        templates[0][2] = "request";
        templates[0][3] = "for";
        templates[0][4] = "{ethAddr}";
        return templates;
    }

    /// @inheritdoc EmailAccountRecovery
    function recoverySubjectTemplates()
        public
        pure
        override
        returns (string[][] memory)
    {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](7);
        templates[0][0] = "Recover";
        templates[0][1] = "account";
        templates[0][2] = "{ethAddr}";
        templates[0][3] = "using";
        templates[0][4] = "recovery";
        templates[0][5] = "module";
        templates[0][6] = "{ethAddr}";
        return templates;
    }

    function acceptGuardian(
        address guardian,
        uint templateIdx,
        bytes[] memory subjectParams,
        bytes32
    ) internal override {
        if (guardian == address(0)) revert InvalidGuardian();
        if (templateIdx != 0) revert InvalidTemplateIndex();
        if (subjectParams.length != 1) revert InvalidSubjectParams();

        address accountInEmail = abi.decode(subjectParams[0], (address));

        address accountForRouter = getAccountForRouter(msg.sender);
        if (accountForRouter != accountInEmail)
            revert InvalidAccountForRouter();

        if (!isGuardian(guardian, accountInEmail))
            revert GuardianInvalidForAccountInEmail();

        GuardianStatus guardianStatus = getGuardianStatus(
            accountInEmail,
            guardian
        );
        if (guardianStatus == GuardianStatus.ACCEPTED)
            revert GuardianAlreadyAccepted();

        updateGuardian(accountInEmail, guardian, GuardianStatus.ACCEPTED);
    }

    function processRecovery(
        address guardian,
        uint templateIdx,
        bytes[] memory subjectParams,
        bytes32
    ) internal override {
        if (guardian == address(0)) revert InvalidGuardian();
        if (templateIdx != 0) revert InvalidTemplateIndex();
        if (subjectParams.length != 2) revert InvalidSubjectParams();

        address accountInEmail = abi.decode(subjectParams[0], (address));
        address recoveryModuleInEmail = abi.decode(subjectParams[1], (address));

        address accountForRouter = getAccountForRouter(msg.sender);
        if (accountForRouter != accountInEmail)
            revert InvalidAccountForRouter();

        if (!isGuardian(guardian, accountInEmail))
            revert GuardianInvalidForAccountInEmail();

        GuardianStatus guardianStatus = getGuardianStatus(
            accountInEmail,
            guardian
        );
        if (guardianStatus == GuardianStatus.REQUESTED)
            revert GuardianHasNotAccepted();

        RecoveryRequest memory recoveryRequest = recoveryRequests[
            accountInEmail
        ];
        if (recoveryRequest.executeAfter > 0) {
            revert RecoveryAlreadyInitiated();
        }

        recoveryRequests[accountInEmail].approvalCount++;

        uint256 threshold = getGuardianConfig(accountInEmail).threshold;
        if (recoveryRequests[accountInEmail].approvalCount >= threshold) {
            uint256 executeAfter = block.timestamp +
                recoveryDelays[accountInEmail];

            recoveryRequests[accountInEmail].executeAfter = executeAfter;
            recoveryRequests[accountInEmail]
                .recoveryModule = recoveryModuleInEmail;

            // emit RecoveryInitiated(accountInEmail, executeAfter);
        }
    }

    function completeRecovery() public override {
        address account = getAccountForRouter(msg.sender);

        RecoveryRequest memory recoveryRequest = recoveryRequests[account];

        uint256 threshold = getGuardianConfig(account).threshold;
        if (recoveryRequest.approvalCount < threshold)
            revert NotEnoughApprovals();

        if (block.timestamp < recoveryRequest.executeAfter)
            revert DelayNotPassed();

        delete recoveryRequests[account];

        IRecoveryModule(recoveryRequest.recoveryModule).recover(
            abi.encode(account)
        );

        // emit RecoveryCompleted(account);
    }

    /// @inheritdoc IZkEmailRecovery
    function cancelRecovery() external {
        address account = msg.sender;
        delete recoveryRequests[account];
        emit RecoveryCancelled(account);
    }

    /// @inheritdoc IZkEmailRecovery
    function updateRecoveryDelay(uint256 recoveryDelay) external {
        // TODO: add implementation
    }
}