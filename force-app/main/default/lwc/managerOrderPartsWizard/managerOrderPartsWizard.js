import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getOrderPartsContext from '@salesforce/apex/ManagerOrderPartsController.getOrderPartsContext';
import saveOrderingDecisions from '@salesforce/apex/ManagerOrderPartsController.saveOrderingDecisions';
import getTechnicianRequestedPartContext from '@salesforce/apex/ManagerOrderPartsController.getTechnicianRequestedPartContext';
import orderTechnicianRequestedPart from '@salesforce/apex/ManagerOrderPartsController.orderTechnicianRequestedPart';

export default class ManagerOrderPartsWizard extends LightningElement {

    @api recordId;
    @api mode = 'work-order';

    context;
    parts = [];
    saveResult;

    currentStep = 1;
    isLoading = true;
    isSaving = false;

    errorMessage = '';
    saveErrorMessage = '';

    supplierName = '';
    supplierPhone = '';
    orderUrl = '';
    technicianOrderConfirmed = false;

    // =========================================================
    // INITIAL LOAD
    // =========================================================

    async connectedCallback() {
        await this.loadOrderingContext();
    }

    async loadOrderingContext() {
        this.isLoading = true;
        this.errorMessage = '';
        this.saveErrorMessage = '';
        this.currentStep = 1;

        try {
            if (this.isTechnicianRequestMode) await this.loadTechnicianRequestedPartContext();
            else await this.loadWorkOrderPartsContext();
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadWorkOrderPartsContext() {
        this.context = await getOrderPartsContext({ workOrderId: this.recordId });

        if (!this.context?.isEligible) {
            this.errorMessage = this.context?.eligibilityMessage || 'This Work Order is not available for parts ordering.';
            return;
        }

        if (!this.context?.requestedParts || this.context.requestedParts.length === 0) {
            this.errorMessage = this.context?.eligibilityMessage || 'There are no Requested parts remaining on this Work Order.';
            return;
        }

        this.parts = this.context.requestedParts.map((part, index) => this.normalizePart(part, index));
    }

    async loadTechnicianRequestedPartContext() {
        this.context = await getTechnicianRequestedPartContext({ workOrderPartId: this.recordId });

        if (!this.context?.isEligible) {
            this.errorMessage = this.context?.eligibilityMessage || 'This technician-requested part is not available for ordering.';
            return;
        }

        if (!this.context?.requestedPart) {
            this.errorMessage = 'The requested Work Order Part could not be loaded.';
            return;
        }

        const part = this.normalizePart(this.context.requestedPart, 0);
        this.parts = [part];
        this.supplierName = part.supplierName || '';
        this.supplierPhone = part.supplierPhone || '';
        this.orderUrl = part.orderUrl || '';
        this.technicianOrderConfirmed = false;
    }

    normalizePart(part, index) {
        return {
            ...part,
            rowNumber: index + 1,
            keepRequired: true,
            orderConfirmed: false,
            hasSupplierPhone: Boolean(part.supplierPhone),
            phoneHref: this.buildPhoneHref(part.supplierPhone),
            hasOrderUrl: Boolean(part.orderUrl)
        };
    }

    buildPhoneHref(phone) {
        if (!phone) return null;
        return `tel:${phone.replace(/[^0-9+]/g, '')}`;
    }

    // =========================================================
    // MODE / HEADER
    // =========================================================

    get isTechnicianRequestMode() {
        return this.mode === 'technician-request';
    }

    get workOrderNumber() {
        return this.context?.workOrderNumber ? `WO ${this.context.workOrderNumber}` : 'Work Order';
    }

    get assetName() {
        return this.context?.assetName || 'Machine not available';
    }

    get accountName() {
        return this.context?.accountName || 'Customer not available';
    }

    get dispatchStatus() {
        return this.context?.dispatchStatus || 'Not Set';
    }

    get requestedCountLabel() {
        if (this.isTechnicianRequestMode) return 'Technician request';
        const count = this.context?.requestedPartCount || 0;
        return count === 1 ? '1 requested part' : `${count} requested parts`;
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

    get isStepThree() {
        return this.currentStep === 3;
    }

    get stepOneClass() {
        return this.currentStep === 1 ? 'progress-step active' : 'progress-step complete';
    }

    get stepTwoClass() {
        if (this.currentStep === 2) return 'progress-step active';
        return this.currentStep > 2 ? 'progress-step complete' : 'progress-step';
    }

    get stepThreeClass() {
        return this.currentStep === 3 ? 'progress-step active' : 'progress-step';
    }

    get technicianStepOneClass() {
        return this.currentStep === 1 ? 'progress-step active' : 'progress-step complete';
    }

    get technicianStepTwoClass() {
        return this.currentStep === 2 ? 'progress-step active' : 'progress-step';
    }

    // =========================================================
    // WORK ORDER MODE — STEP 1
    // =========================================================

    get reviewParts() {
        return this.parts.map(part => ({
            ...part,
            rowClass: part.keepRequired ? 'part-review-row' : 'part-review-row part-review-row-removed',
            statusLabel: part.keepRequired ? 'Required' : 'Remove'
        }));
    }

    get keptParts() {
        return this.parts.filter(part => part.keepRequired);
    }

    get removedParts() {
        return this.parts.filter(part => !part.keepRequired);
    }

    get hasKeptParts() {
        return this.keptParts.length > 0;
    }

    get keptPartCountLabel() {
        const count = this.keptParts.length;
        return count === 1 ? '1 part remains required' : `${count} parts remain required`;
    }

    get removedPartCountLabel() {
        const count = this.removedParts.length;
        return count === 1 ? '1 part will be removed' : `${count} parts will be removed`;
    }

    get hasRemovedParts() {
        return this.removedParts.length > 0;
    }

    handleKeepRequiredChange(event) {
        const partId = event.currentTarget.dataset.id, keepRequired = event.target.checked;

        this.parts = this.parts.map(part => {
            if (part.workOrderPartId !== partId) return part;
            return { ...part, keepRequired, orderConfirmed: keepRequired ? part.orderConfirmed : false };
        });
    }

    handleContinueToOrders() {
        this.saveErrorMessage = '';
        this.currentStep = 2;
    }

    // =========================================================
    // WORK ORDER MODE — STEP 2
    // =========================================================

    get orderParts() {
        return this.keptParts;
    }

    get orderPartCountLabel() {
        const count = this.orderParts.length;
        return count === 1 ? '1 part to order' : `${count} parts to order`;
    }

    handleOrderConfirmedChange(event) {
        const partId = event.currentTarget.dataset.id, orderConfirmed = event.target.checked;
        this.parts = this.parts.map(part => part.workOrderPartId === partId ? { ...part, orderConfirmed } : part);
    }

    get confirmedOrderCount() {
        return this.parts.filter(part => part.keepRequired && part.orderConfirmed).length;
    }

    get confirmedOrderCountLabel() {
        const count = this.confirmedOrderCount;
        return count === 1 ? '1 order confirmed' : `${count} orders confirmed`;
    }

    handleContinueToSummary() {
        this.saveErrorMessage = '';
        this.currentStep = 3;
    }

    // =========================================================
    // WORK ORDER MODE — STEP 3
    // =========================================================

    get orderedParts() {
        return this.parts.filter(part => part.keepRequired && part.orderConfirmed);
    }

    get remainingParts() {
        return this.parts.filter(part => part.keepRequired && !part.orderConfirmed);
    }

    get cancelledParts() {
        return this.parts.filter(part => !part.keepRequired);
    }

    get hasOrderedParts() {
        return this.orderedParts.length > 0;
    }

    get hasRemainingParts() {
        return this.remainingParts.length > 0;
    }

    get hasCancelledParts() {
        return this.cancelledParts.length > 0;
    }

    get hasExistingCommittedParts() {
        return Boolean(this.context?.hasExistingCommittedParts);
    }

    get orderedPartCountLabel() {
        const count = this.orderedParts.length;
        return count === 1 ? '1 part to record as ordered' : `${count} parts to record as ordered`;
    }

    get remainingPartCountLabel() {
        const count = this.remainingParts.length;
        return count === 1 ? '1 part will remain to order' : `${count} parts will remain to order`;
    }

    get cancelledPartCountLabel() {
        const count = this.cancelledParts.length;
        return count === 1 ? '1 part will be removed from this request.' : `${count} parts will be removed from this request.`;
    }

    get previewWorkOrderStatus() {
        if (this.hasRemainingParts) return 'Parts to Order';
        if (this.hasOrderedParts || this.hasExistingCommittedParts) return 'Waiting on Parts';
        return 'Ready_to_Assign';
    }

    get nextSummaryStepNumber() {
        return this.hasRemainingParts ? '3' : '2';
    }

    get nextStepLabel() {
        switch (this.previewWorkOrderStatus) {
            case 'Parts to Order': return 'Complete Remaining Parts Orders';
            case 'Waiting on Parts': return 'Waiting on Parts';
            case 'Ready_to_Assign': return 'Assign a Technician';
            default: return 'Next Step';
        }
    }

    get nextStepMessage() {
        switch (this.previewWorkOrderStatus) {
            case 'Parts to Order':
                return 'One or more required parts still need to be ordered. When you click Done, this Work Order will remain in Parts to Order.';
            case 'Waiting on Parts':
                return 'No Requested parts will remain. When you click Done, this Work Order will move to Waiting on Parts.';
            case 'Ready_to_Assign':
                return 'No parts will remain required for this repair. When you click Done, this Work Order will move to Ready to Assign.';
            default:
                return '';
        }
    }

    get nextStepStatusLabel() {
        return this.previewWorkOrderStatus === 'Ready_to_Assign' ? 'Ready to Assign' : this.previewWorkOrderStatus;
    }

    get isDoneDisabled() {
        return this.isSaving || !this.recordId;
    }

    buildDecisions() {
        return this.parts.map(part => ({
            workOrderPartId: part.workOrderPartId,
            keepRequired: part.keepRequired,
            orderConfirmed: part.keepRequired ? part.orderConfirmed : false
        }));
    }

    // =========================================================
    // TECHNICIAN REQUEST MODE
    // =========================================================

    get technicianPart() {
        return this.parts?.[0] || {};
    }

    get technicianHasNotes() {
        return Boolean(this.technicianPart?.notes);
    }

    get technicianPhoneHref() {
        return this.buildPhoneHref(this.supplierPhone);
    }

    get hasTechnicianPhone() {
        return Boolean(this.supplierPhone?.trim());
    }

    get hasTechnicianOrderUrl() {
        return Boolean(this.orderUrl?.trim());
    }

    get isTechnicianOrderReady() {
        return Boolean(
            this.technicianOrderConfirmed &&
            this.supplierName?.trim() &&
            this.supplierPhone?.trim() &&
            this.orderUrl?.trim()
        );
    }

    get isTechnicianContinueDisabled() {
        return this.isSaving || !this.isTechnicianOrderReady;
    }

    get isTechnicianDoneDisabled() {
        return this.isSaving || !this.recordId || !this.isTechnicianOrderReady;
    }

    handleSupplierNameChange(event) {
        this.supplierName = event.target.value;
        this.saveErrorMessage = '';
    }

    handleSupplierPhoneChange(event) {
        this.supplierPhone = event.target.value;
        this.saveErrorMessage = '';
    }

    handleOrderUrlChange(event) {
        this.orderUrl = event.target.value;
        this.saveErrorMessage = '';
    }

    handleTechnicianOrderConfirmedChange(event) {
        this.technicianOrderConfirmed = event.target.checked;
        this.saveErrorMessage = '';
    }

    validateTechnicianOrderInputs() {
        const inputs = [...this.template.querySelectorAll('.technician-order-input')];

        return inputs.reduce((isValid, input) => {
            input.reportValidity();
            return input.checkValidity() && isValid;
        }, true);
    }

    handleTechnicianContinue() {
        if (this.isTechnicianContinueDisabled || !this.validateTechnicianOrderInputs()) return;

        this.saveErrorMessage = '';
        this.currentStep = 2;
    }

    async handleTechnicianDone() {
        if (this.isTechnicianDoneDisabled) return;

        this.isSaving = true;
        this.saveErrorMessage = '';

        try {
            this.saveResult = await orderTechnicianRequestedPart({
                workOrderPartId: this.recordId,
                supplierName: this.supplierName.trim(),
                supplierPhone: this.supplierPhone.trim(),
                orderUrl: this.orderUrl.trim()
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Supplier Order Recorded',
                message: this.saveResult?.nextStepMessage || 'The technician-requested part was recorded as Ordered.',
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('complete', {
                detail: {
                    mode: 'technician-request',
                    workOrderPartId: this.saveResult?.workOrderPartId || this.recordId,
                    workOrderId: this.saveResult?.workOrderId || this.context?.workOrderId,
                    workOrderStatus: this.saveResult?.workOrderStatus || this.context?.dispatchStatus,
                    orderedPartCount: 1,
                    remainingPartCount: 0,
                    cancelledPartCount: 0,
                    nextStepLabel: this.saveResult?.nextStepLabel,
                    nextStepMessage: this.saveResult?.nextStepMessage
                }
            }));
        } catch (error) {
            this.saveErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Unable to Record Supplier Order',
                message: this.saveErrorMessage,
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================
    // NAVIGATION
    // =========================================================

    handleBack() {
        if (this.isSaving) return;

        this.saveErrorMessage = '';

        if (this.currentStep === 3) {
            this.currentStep = 2;
            return;
        }

        if (this.currentStep === 2) this.currentStep = 1;
    }

    handleCancel() {
        if (this.isSaving) return;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // =========================================================
    // WORK ORDER MODE — SAVE
    // =========================================================

    async handleDone() {
        if (this.isDoneDisabled) return;

        this.isSaving = true;
        this.saveErrorMessage = '';

        try {
            const decisions = this.buildDecisions();
            this.saveResult = await saveOrderingDecisions({ workOrderId: this.recordId, decisions });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Parts Ordering Saved',
                message: this.saveResult?.nextStepMessage || 'Parts ordering progress was saved.',
                variant: 'success'
            }));

            this.dispatchEvent(new CustomEvent('complete', {
                detail: {
                    workOrderId: this.saveResult?.workOrderId || this.recordId,
                    workOrderStatus: this.saveResult?.workOrderStatus,
                    assetStatus: this.saveResult?.assetStatus,
                    orderedPartCount: this.saveResult?.orderedPartCount || 0,
                    remainingPartCount: this.saveResult?.remainingPartCount || 0,
                    cancelledPartCount: this.saveResult?.cancelledPartCount || 0,
                    nextStepLabel: this.saveResult?.nextStepLabel,
                    nextStepMessage: this.saveResult?.nextStepMessage
                }
            }));
        } catch (error) {
            this.saveErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Unable to Save Parts Ordering',
                message: this.saveErrorMessage,
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================
    // ERROR HANDLING
    // =========================================================

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred.';
    }
}