import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getReceivePartsContext
    from '@salesforce/apex/ManagerReceivePartsController.getReceivePartsContext';

import receiveParts
    from '@salesforce/apex/ManagerReceivePartsController.receiveParts';

export default class ManagerReceivePartsWizard extends LightningElement {

    @api recordId;

    context;
    parts = [];
    saveResult;

    currentStep = 1;

    isLoading = true;
    isSaving = false;
    showSuccessConfirmation = false;

    errorMessage = '';
    saveErrorMessage = '';

    // =========================================================
    // INITIAL LOAD
    // =========================================================

    async connectedCallback() {
        await this.loadReceivePartsContext();
    }

    async loadReceivePartsContext() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            this.context = await getReceivePartsContext({
                workOrderId: this.recordId
            });

            if (!this.context?.isEligible) {
                this.errorMessage =
                    this.context?.eligibilityMessage ||
                    'This Work Order is not available for parts receipt.';
                return;
            }

            if (
                !this.context?.hasReceivableParts ||
                !this.context?.receivableParts?.length
            ) {
                this.errorMessage =
                    this.context?.eligibilityMessage ||
                    'There are no Ordered or Shipped parts available to receive.';
                return;
            }

            this.parts = this.context.receivableParts.map(
                (part, index) => ({
                    ...part,
                    rowNumber: index + 1,
                    receivedSelected: false
                })
            );

        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================
    // HEADER
    // =========================================================

    get workOrderNumber() {
        return this.context?.workOrderNumber
            ? `WO ${this.context.workOrderNumber}`
            : 'Work Order';
    }

    get assetName() {
        return this.context?.assetName ||
            'Machine not available';
    }

    get dispatchStatus() {
        return this.context?.dispatchStatus ||
            'Not Set';
    }

    get receivableCountLabel() {
        const count =
            this.context?.receivablePartCount || 0;

        return count === 1
            ? '1 part available'
            : `${count} parts available`;
    }

    // =========================================================
    // STEP STATE
    // =========================================================

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get stepOneClass() {
        return this.currentStep === 1
            ? 'progress-step active'
            : 'progress-step complete';
    }

    get stepTwoClass() {
        return this.currentStep === 2
            ? 'progress-step active'
            : 'progress-step';
    }

    // =========================================================
    // STEP 1 — CONFIRM RECEIVED PARTS
    // =========================================================

    get reviewParts() {
        return this.parts.map(
            part => ({
                ...part,

                rowClass: part.receivedSelected
                    ? 'receipt-part-row receipt-part-row-selected'
                    : 'receipt-part-row',

                statusClass:
                    part.orderStatus === 'Shipped'
                        ? 'part-status part-status-shipped'
                        : 'part-status part-status-ordered'
            })
        );
    }

    get selectedParts() {
        return this.parts.filter(
            part => part.receivedSelected
        );
    }

    get selectedPartCount() {
        return this.selectedParts.length;
    }

    get selectedPartCountLabel() {
        const count =
            this.selectedPartCount;

        return count === 1
            ? '1 part selected'
            : `${count} parts selected`;
    }

    get selectedUnitCount() {
        return this.selectedParts.reduce(
            (total, part) =>
                total + Number(part.quantity || 0),
            0
        );
    }

    get selectedUnitCountLabel() {
        const count =
            this.selectedUnitCount;

        return count === 1
            ? '1 unit'
            : `${count} units`;
    }

    get hasSelectedParts() {
        return this.selectedPartCount > 0;
    }

    get isContinueDisabled() {
        return (
            !this.hasSelectedParts ||
            this.isSaving
        );
    }

    handleReceivedChange(event) {
        const partId =
            event.currentTarget.dataset.id;

        const receivedSelected =
            event.target.checked;

        this.parts = this.parts.map(
            part => {
                if (
                    part.workOrderPartId !==
                    partId
                ) {
                    return part;
                }

                return {
                    ...part,
                    receivedSelected
                };
            }
        );

        this.saveErrorMessage = '';
    }

    handleContinue() {
        if (this.isContinueDisabled) {
            return;
        }

        this.saveErrorMessage = '';
        this.currentStep = 2;
    }

    // =========================================================
    // STEP 2 — RECEIPT SUMMARY / PREVIEW
    // =========================================================

    get receivedPartCountLabel() {
        const count =
            this.selectedPartCount;

        return count === 1
            ? '1 part to receive'
            : `${count} parts to receive`;
    }

    /*
     * The context counts Requested + Ordered + Shipped as
     * outstanding.
     *
     * Every selected record is currently Ordered or Shipped,
     * therefore it is currently part of that outstanding total.
     *
     * This preview removes the selected receipt records without
     * performing any DML.
     */
    get previewOutstandingPartCount() {
        const currentOutstanding =
            Number(
                this.context?.outstandingPartCount || 0
            );

        return Math.max(
            currentOutstanding -
                this.selectedPartCount,
            0
        );
    }

    get previewOutstandingUnitCount() {
        const currentOutstandingUnits =
            Number(
                this.context?.outstandingUnitCount || 0
            );

        return Math.max(
            currentOutstandingUnits -
                this.selectedUnitCount,
            0
        );
    }

    get previewReadyToAssign() {
        return this.previewOutstandingPartCount === 0;
    }

    get previewWorkOrderStatus() {
        return this.previewReadyToAssign
            ? 'Ready_to_Assign'
            : 'Waiting on Parts';
    }

    get nextStepTitle() {
        return this.previewReadyToAssign
            ? 'Assign a Technician'
            : 'Wait for Remaining Parts';
    }

    get nextStepStatusLabel() {
        return this.previewReadyToAssign
            ? 'Ready to Assign'
            : 'Waiting on Parts';
    }

    get nextStepMessage() {
        if (this.previewReadyToAssign) {
            return (
                'These are the final outstanding required parts. ' +
                'When you click Done, the Work Order and machine will move to Ready to Assign.'
            );
        }

        return (
            'Additional required parts will still be outstanding. ' +
            'When you click Done, this Work Order will remain in Waiting on Parts.'
        );
    }

    get outstandingPreviewLabel() {
        const count =
            this.previewOutstandingPartCount;

        if (count === 0) {
            return 'No outstanding parts will remain';
        }

        return count === 1
            ? '1 part will remain outstanding'
            : `${count} parts will remain outstanding`;
    }

    get nextStepStatusClass() {
        return this.previewReadyToAssign
            ? 'next-status-pill next-status-ready'
            : 'next-status-pill next-status-waiting';
    }

    get isDoneDisabled() {
        return (
            this.isSaving ||
            !this.recordId ||
            !this.hasSelectedParts
        );
    }

    // =========================================================
    // NAVIGATION
    // =========================================================

    handleBack() {
        if (this.isSaving) {
            return;
        }

        this.saveErrorMessage = '';

        if (this.currentStep === 2) {
            this.currentStep = 1;
        }
    }

    handleCancel() {
        if (
            this.isSaving ||
            this.showSuccessConfirmation
        ) {
            return;
        }

        this.dispatchEvent(
            new CustomEvent('cancel')
        );
    }

    // =========================================================
    // SAVE
    // =========================================================

    async handleDone() {
        if (this.isDoneDisabled) {
            return;
        }

        this.isSaving = true;
        this.saveErrorMessage = '';

        try {
            const receivedPartIds =
                this.selectedParts.map(
                    part =>
                        part.workOrderPartId
                );

            this.saveResult =
                await receiveParts({
                    workOrderId:
                        this.recordId,
                    receivedPartIds
                });

            /*
             * Keep the manager modal open.
             * The Operations Center remains dimmed/blurred while
             * this compact confirmation is displayed.
             */
            this.showSuccessConfirmation =
                true;

        } catch (error) {
            this.saveErrorMessage =
                this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title:
                        'Unable to Receive Parts',
                    message:
                        this.saveErrorMessage,
                    variant:
                        'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================
    // SUCCESS CONFIRMATION
    // =========================================================

    get successReadyToAssign() {
        return Boolean(
            this.saveResult?.readyToAssign
        );
    }

    get successHeading() {
        return this.successReadyToAssign
            ? 'All Required Parts Received'
            : 'Parts Received Successfully';
    }

    get successMessage() {
        return (
            this.saveResult?.message ||
            'The selected Work Order Parts were updated successfully.'
        );
    }

    get successStatusLabel() {
        return this.successReadyToAssign
            ? 'Ready to Assign'
            : 'Waiting on Parts';
    }

    get successStatusClass() {
        return this.successReadyToAssign
            ? 'success-status-pill success-status-ready'
            : 'success-status-pill success-status-waiting';
    }

    get successNextStepTitle() {
        return this.successReadyToAssign
            ? 'Next: Assign a Technician'
            : 'Next: Wait for Remaining Parts';
    }

    get successNextStepMessage() {
        if (this.successReadyToAssign) {
            return (
                'No Requested, Ordered, or Shipped parts remain. ' +
                'The Work Order is ready for technician assignment.'
            );
        }

        const count =
            Number(
                this.saveResult?.outstandingPartCount || 0
            );

        return count === 1
            ? '1 required part is still outstanding, so this Work Order will remain in Waiting on Parts.'
            : `${count} required parts are still outstanding, so this Work Order will remain in Waiting on Parts.`;
    }

    handleSuccessClose() {
        const result =
            this.saveResult || {};

        this.dispatchEvent(
            new CustomEvent(
                'complete',
                {
                    detail: {
                        workOrderId:
                            result.workOrderId ||
                            this.recordId,

                        workOrderStatus:
                            result.workOrderStatus,

                        assetStatus:
                            result.assetStatus,

                        receivedPartCount:
                            result.receivedPartCount || 0,

                        receivedUnitCount:
                            result.receivedUnitCount || 0,

                        outstandingPartCount:
                            result.outstandingPartCount || 0,

                        outstandingUnitCount:
                            result.outstandingUnitCount || 0,

                        readyToAssign:
                            result.readyToAssign === true,

                        nextStepLabel:
                            result.nextStepLabel,

                        message:
                            result.message
                    }
                }
            )
        );
    }

    // =========================================================
    // ERROR HANDLING
    // =========================================================

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'An unexpected error occurred.';
    }
}