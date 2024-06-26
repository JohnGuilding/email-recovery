// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";

import {EmailAuthMsg, EmailProof} from "ether-email-auth/packages/contracts/src/EmailAuth.sol";

import {ZkEmailRecovery} from "src/ZkEmailRecovery.sol";
import {IEmailAccountRecovery} from "src/interfaces/IEmailAccountRecovery.sol";
import {IntegrationBase} from "../IntegrationBase.t.sol";

abstract contract OwnableValidatorBase is IntegrationBase {
    ZkEmailRecovery zkEmailRecovery;

    function setUp() public virtual override {
        super.setUp();

        // Deploy ZkEmailRecovery
        zkEmailRecovery = new ZkEmailRecovery(
            address(verifier),
            address(ecdsaOwnedDkimRegistry),
            address(emailAuthImpl)
        );

        // Compute guardian addresses
        guardian1 = zkEmailRecovery.computeEmailAuthAddress(accountSalt1);
        guardian2 = zkEmailRecovery.computeEmailAuthAddress(accountSalt2);
        guardian3 = zkEmailRecovery.computeEmailAuthAddress(accountSalt3);

        guardians = new address[](3);
        guardians[0] = guardian1;
        guardians[1] = guardian2;
        guardians[2] = guardian3;
    }

    // Helper functions

    function generateMockEmailProof(
        string memory subject,
        bytes32 nullifier,
        bytes32 accountSalt
    ) public returns (EmailProof memory) {
        EmailProof memory emailProof;
        emailProof.domainName = "gmail.com";
        emailProof.publicKeyHash = bytes32(
            vm.parseUint(
                "6632353713085157925504008443078919716322386156160602218536961028046468237192"
            )
        );
        emailProof.timestamp = block.timestamp;
        emailProof.maskedSubject = subject;
        emailProof.emailNullifier = nullifier;
        emailProof.accountSalt = accountSalt;
        emailProof.isCodeExist = true;
        emailProof.proof = bytes("0");

        return emailProof;
    }

    function acceptGuardian(
        address account,
        // ZkEmailRecovery zkEmailRecovery,
        address router,
        string memory subject,
        bytes32 nullifier,
        bytes32 accountSalt,
        uint256 templateIdx
    ) public {
        EmailProof memory emailProof = generateMockEmailProof(
            subject,
            nullifier,
            accountSalt
        );

        bytes[] memory subjectParamsForAcceptance = new bytes[](1);
        subjectParamsForAcceptance[0] = abi.encode(account);
        EmailAuthMsg memory emailAuthMsg = EmailAuthMsg({
            templateId: zkEmailRecovery.computeAcceptanceTemplateId(
                templateIdx
            ),
            subjectParams: subjectParamsForAcceptance,
            skipedSubjectPrefix: 0,
            proof: emailProof
        });

        IEmailAccountRecovery(router).handleAcceptance(
            emailAuthMsg,
            templateIdx
        );
    }

    function handleRecovery(
        address account,
        address newOwner,
        address recoveryModule,
        address router,
        string memory subject,
        bytes32 nullifier,
        bytes32 accountSalt,
        uint256 templateIdx
    ) public {
        EmailProof memory emailProof = generateMockEmailProof(
            subject,
            nullifier,
            accountSalt
        );

        bytes[] memory subjectParamsForRecovery = new bytes[](3);
        subjectParamsForRecovery[0] = abi.encode(account);
        subjectParamsForRecovery[1] = abi.encode(newOwner);
        subjectParamsForRecovery[2] = abi.encode(recoveryModule);

        EmailAuthMsg memory emailAuthMsg = EmailAuthMsg({
            templateId: zkEmailRecovery.computeRecoveryTemplateId(templateIdx),
            subjectParams: subjectParamsForRecovery,
            skipedSubjectPrefix: 0,
            proof: emailProof
        });
        IEmailAccountRecovery(router).handleRecovery(emailAuthMsg, templateIdx);
    }
}
