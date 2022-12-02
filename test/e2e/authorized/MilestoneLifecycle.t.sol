// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {E2eTest} from "test/e2e/E2eTest.sol";

import {IProposalFactory} from "src/factories/ProposalFactory.sol";
import {IProposal} from "src/proposal/Proposal.sol";

import {MilestoneManager} from "src/modules/MilestoneManager.sol";
import {PaymentProcessor} from "src/modules/PaymentProcessor.sol";
import {IPaymentClient} from "src/modules/mixins/IPaymentClient.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

/**
 * E2e test demonstrating how to add, start, and complete a Milestone.
 */
contract MilestoneLifecycle is E2eTest {
    address alice = address(0xA11CE);
    address bob = address(0x606);

    address funder1 = address(0xF1);
    address funder2 = address(0xF2);

    ERC20Mock token = new ERC20Mock("Mock", "MOCK");

    function test_e2e_MilestoneLifecycle() public {
        // First, we create a new proposal.
        IProposalFactory.ProposalConfig memory proposalConfig = IProposalFactory
            .ProposalConfig({owner: address(this), token: token});

        IProposal proposal = _createNewProposalWithAllModules(proposalConfig);

        // Now we add a few milestones.
        // For that, we need to access the proposal's milestone module.
        // Note that we normally receive the proposal's module implementations
        // from the emitted events during the proposal creation.
        // However, in Solidity it is not possible to access events, so we
        // copied the module's (deterministic in this test) address from the
        // logs.
        MilestoneManager milestoneManager =
            MilestoneManager(0xa78f6C9322C3f1b396720945B6C3035A4a1B3d70);

        milestoneManager.addMilestone(
            1 weeks,
            1000e18,
            "My first Milestone",
            "Here could be a more detailed description"
        );
        milestoneManager.addMilestone(
            2 weeks,
            5000e18,
            "Second Milestone",
            "The second milestone, right after the first one"
        );

        // Before we can start a milestone, two things need to be present:
        // 1. A non-empty list of contributors in the proposal
        // 2. The amount of funding to pay the contributors for the milestone

        // So lets add Alice and Bob as contributors to the proposal.
        proposal.addContributor(alice, "Alice", "Smart Contract Engineer", 1);
        proposal.addContributor(bob, "Bob", "Web Developer", 1);
        // Note the last argument being the salary for the contributors.
        // However, the salary is not yet taken into in the Milestone module.
        // The milestone's budget is shared equally between all contributors.

        assertTrue(proposal.isContributor(alice));
        assertTrue(proposal.isContributor(bob));

        // Seeing this great working on the proposal, funder1 decides to fund
        // the proposal with 1k of tokens.
        token.mint(funder1, 1000e18);

        vm.startPrank(funder1);
        {
            token.approve(address(proposal), 1000e18);
            proposal.deposit(1000e18, funder1);
        }
        vm.stopPrank();

        // The proposal now has 1k tokens of funding. Exactly the amount needed
        // for the first milestone.
        assertEq(proposal.totalAssets(), 1000e18);

        // IMPORTANT
        // =========
        // Due to how ERC-4626 works, it is not possible to deposit tokens once
        // the vault reached a balance of zero.
        token.mint(address(proposal), 1);

        // Now we start the first milestone.
        milestoneManager.startNextMilestone();

        // Starting a milestone DOES NOT itself pay the contributors but
        // creates set set of payment orders inside the module that can be
        // processed by a PaymentProcessor module. Note however, that the
        // orders are guaranteed to be payable, i.e. the tokens are already
        // fetched from the proposal.
        assertEq(token.balanceOf(address(proposal)), 1);

        // The address of the proposal's PaymentProcessor can be read from the
        // logs during the proposal's creation.
        PaymentProcessor paymentProcessor =
            PaymentProcessor(0xf5Ba21691a8bC011B7b430854B41d5be0B78b938);

        // The PaymentProcessor's `processPayments()` function is publicly
        // callable. This ensures the contributors can call the function too,
        // guaranteeing their payment.
        vm.prank(alice);
        paymentProcessor.processPayments(
            IPaymentClient(address(milestoneManager))
        );

        assertEq(token.balanceOf(alice), 1000e18 / 2);
        assertEq(token.balanceOf(bob), 1000e18 / 2);

        // Lets wait some time now for Alice and Bob to submit their work for
        // the milestone.
        vm.warp(block.timestamp + 3 days);

        // After 3 days, Bob is ready to submit the milestone.
        // For that, he needs to provide the milestone's id (1 in this case, as
        // it's) the first milestone, and additional data.
        // The submission data can not be empty, and is intended for off-chain
        // systems to check Bob's work.
        vm.prank(bob);
        milestoneManager.submitMilestone({
            id: 1,
            submissionData: bytes("https://bob.com/paper-for-milestone.pdf")
        });

        // Now some authorized addresses need to either mark the milestone as
        // complete or decline Bob's submission. Declining a submission makes
        // it possible for contributors to submit data again.
        milestoneManager.completeMilestone(1);

        // Wuhuu.. The first milestone is completed.

        // Sadly we can not start the next milestone... There is not funding
        // yet.
        // Luckily funder2 comes in and deposits some tokens.
        // Eventhough the milestone only needs 5k of tokens, funder2 deposits
        // 10k.
        token.mint(funder2, 10_000e18);

        vm.startPrank(funder2);
        {
            token.approve(address(proposal), 10_000e18);
            proposal.deposit(10_000e18, funder2);
        }
        vm.stopPrank();

        // Note that we can not yet start the next milestone before the
        // previous' milestone's duration is not over.
        // This is independent whether the milestone is completed or not.
        vm.warp(block.timestamp + 1 weeks);

        // Now start the next proposal...
        milestoneManager.startNextMilestone();
        // ...which leaves 5k of tokens left in the proposal.
        assertEq(token.balanceOf(address(proposal)), 5000e18 + 1);

        // These tokens can now be withdrawn by funder1 and funder2.
        vm.startPrank(funder1);
        {
            proposal.redeem(proposal.balanceOf(funder1), funder1, funder1);
        }
        vm.stopPrank();
        vm.startPrank(funder2);
        {
            proposal.redeem(proposal.balanceOf(funder2), funder2, funder2);
        }
        vm.stopPrank();

        //milestoneManager.startNextMilestone();
    }
}