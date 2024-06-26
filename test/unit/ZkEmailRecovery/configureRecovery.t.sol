// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {ModuleKitHelpers, ModuleKitUserOp} from "modulekit/ModuleKit.sol";
import {MODULE_TYPE_EXECUTOR, MODULE_TYPE_VALIDATOR} from "modulekit/external/ERC7579.sol";

import {IZkEmailRecovery} from "src/interfaces/IZkEmailRecovery.sol";
import {OwnableValidatorRecoveryModule} from "src/modules/OwnableValidatorRecoveryModule.sol";
import {OwnableValidator} from "src/test/OwnableValidator.sol";
import {GuardianStorage, GuardianStatus} from "src/libraries/EnumerableGuardianMap.sol";
import {UnitBase} from "../UnitBase.t.sol";

contract ZkEmailRecovery_configureRecovery_Test is UnitBase {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    OwnableValidatorRecoveryModule recoveryModule;
    address recoveryModuleAddress;

    function setUp() public override {
        super.setUp();

        recoveryModule = new OwnableValidatorRecoveryModule{salt: "test salt"}(
            address(zkEmailRecovery)
        );
        recoveryModuleAddress = address(recoveryModule);
    }

    function test_ConfigureRecovery_RevertWhen_AlreadyRecovering() public {
        vm.startPrank(accountAddress);
        zkEmailRecovery.configureRecovery(
            recoveryModuleAddress,
            guardians,
            guardianWeights,
            threshold,
            delay,
            expiry
        );
        vm.stopPrank();

        address router = zkEmailRecovery.getRouterForAccount(accountAddress);

        acceptGuardian(
            accountAddress,
            zkEmailRecovery,
            router,
            "Accept guardian request for 0x50Bc6f1F08ff752F7F5d687F35a0fA25Ab20EF52",
            keccak256(abi.encode("nullifier 1")),
            accountSalt1,
            templateIdx
        );

        vm.warp(12 seconds);

        handleRecovery(
            accountAddress,
            newOwner,
            recoveryModuleAddress,
            router,
            zkEmailRecovery,
            "Recover account 0x50Bc6f1F08ff752F7F5d687F35a0fA25Ab20EF52 to new owner 0x7240b687730BE024bcfD084621f794C2e4F8408f using recovery module 0xba3137d856cF201622A2aC83CCd4556982224972",
            keccak256(abi.encode("nullifier 2")),
            accountSalt1,
            templateIdx
        );

        vm.expectRevert(IZkEmailRecovery.RecoveryInProcess.selector);
        vm.startPrank(accountAddress);
        zkEmailRecovery.configureRecovery(
            recoveryModuleAddress,
            guardians,
            guardianWeights,
            threshold,
            delay,
            expiry
        );
        vm.stopPrank();
    }

    // Integration test?
    function test_ConfigureRecovery_RevertWhen_ConfigureRecoveryCalledTwice()
        public
    {
        vm.startPrank(accountAddress);
        zkEmailRecovery.configureRecovery(
            recoveryModuleAddress,
            guardians,
            guardianWeights,
            threshold,
            delay,
            expiry
        );

        vm.expectRevert(IZkEmailRecovery.SetupAlreadyCalled.selector);
        zkEmailRecovery.configureRecovery(
            recoveryModuleAddress,
            guardians,
            guardianWeights,
            threshold,
            delay,
            expiry
        );
        vm.stopPrank();
    }

    function test_ConfigureRecovery_Succeeds() public {
        address expectedRouterAddress = zkEmailRecovery.computeRouterAddress(
            keccak256(abi.encode(accountAddress))
        );

        vm.expectEmit();
        emit IZkEmailRecovery.RecoveryConfigured(
            accountAddress,
            recoveryModuleAddress,
            guardians.length,
            expectedRouterAddress
        );
        vm.startPrank(accountAddress);
        zkEmailRecovery.configureRecovery(
            recoveryModuleAddress,
            guardians,
            guardianWeights,
            threshold,
            delay,
            expiry
        );
        vm.stopPrank();

        IZkEmailRecovery.RecoveryConfig memory recoveryConfig = zkEmailRecovery
            .getRecoveryConfig(accountAddress);
        assertEq(recoveryConfig.recoveryModule, recoveryModuleAddress);
        assertEq(recoveryConfig.delay, delay);
        assertEq(recoveryConfig.expiry, expiry);

        IZkEmailRecovery.GuardianConfig memory guardianConfig = zkEmailRecovery
            .getGuardianConfig(accountAddress);
        assertEq(guardianConfig.guardianCount, guardians.length);
        assertEq(guardianConfig.threshold, threshold);

        GuardianStorage memory guardian = zkEmailRecovery.getGuardian(
            accountAddress,
            guardians[0]
        );
        assertEq(uint256(guardian.status), uint256(GuardianStatus.REQUESTED));
        assertEq(guardian.weight, guardianWeights[0]);

        address accountForRouter = zkEmailRecovery.getAccountForRouter(
            expectedRouterAddress
        );
        assertEq(accountForRouter, accountAddress);

        address routerForAccount = zkEmailRecovery.getRouterForAccount(
            accountAddress
        );
        assertEq(routerForAccount, expectedRouterAddress);
    }
}
