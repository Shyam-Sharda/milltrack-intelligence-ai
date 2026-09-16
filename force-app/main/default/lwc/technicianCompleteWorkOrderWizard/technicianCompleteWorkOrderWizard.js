import { LightningElement, api } from 'lwc';
import getCompletionContext from '@salesforce/apex/TechnicianCompleteWorkOrderController.getCompletionContext';
import completeWorkOrder from '@salesforce/apex/TechnicianCompleteWorkOrderController.completeWorkOrder';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class TechnicianCompleteWorkOrderWizard extends NavigationMixin(LightningElement) {
    _recordId;
    hasLoaded = false;

    context = {};
    repairSummary = '';
    rootCause = '';
    partsUsed = '';
    laborHours;

    isLoading = true;
    isSubmitting = false;
    isSuccess = false;
    isInitialError = false;
    isSubmitError = false;

    inlineError;
    errorMessage;
    maintenanceLogId;
    navigationTimer;

    @api
    get recordId() { return this._recordId; }

    set recordId(value) {
        this._recordId = value;
        if (value && !this.hasLoaded) {
            this.hasLoaded = true;
            this.initialize();
        }
    }

    disconnectedCallback() { window.clearTimeout(this.navigationTimer); }

    async initialize() {
        this.isLoading = true;

        try {
            this.context = await getCompletionContext({ workOrderId: this.recordId });
        } catch (error) {
            this.isInitialError = true;
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRepairSummaryChange(event) {
        this.repairSummary = event.target.value;
        this.inlineError = null;
    }

    handleRootCauseChange(event) {
        this.rootCause = event.target.value;
        this.inlineError = null;
    }

    handlePartsUsedChange(event) {
        this.partsUsed = event.target.value;
        this.inlineError = null;
    }

    handleLaborChange(event) {
        this.laborHours = event.target.value;
        this.inlineError = null;
    }

    async handleSubmit() {
        this.inlineError = null;

        const inputs = [...this.template.querySelectorAll('.form-input')];
        const valid = inputs.reduce((result, input) => {
            input.reportValidity();
            return input.checkValidity() && result;
        }, true);

        if (!valid) return;

        if (!this.repairSummary?.trim()) {
            this.inlineError = 'Enter a Repair Summary.';
            return;
        }

        if (!this.rootCause?.trim()) {
            this.inlineError = 'Enter the Root Cause.';
            return;
        }

        const labor = Number(this.laborHours);

        if (Number.isNaN(labor) || labor <= 0) {
            this.inlineError = 'Labor Hours must be greater than 0.';
            return;
        }

        this.isSubmitting = true;

        try {
            const result = await completeWorkOrder({
                workOrderId: this.recordId,
                repairSummary: this.repairSummary.trim(),
                rootCause: this.rootCause.trim(),
                partsUsed: this.partsUsed?.trim() || null,
                laborHours: labor
            });

            this.maintenanceLogId = result.maintenanceLogId;
            this.isSuccess = true;

            /*
             * Do NOT refresh the Work Order.
             * Completion transfers ownership back to the Service Manager,
             * so the technician may immediately lose access to the Work Order.
             */
            this.navigationTimer = window.setTimeout(() => this.navigateToMaintenanceLog(), 1500);
        } catch (error) {
            this.isSubmitError = true;
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleReturnToForm() {
        this.isSubmitError = false;
        this.errorMessage = null;
        this.inlineError = null;
    }

    handleOpenMaintenanceLog() {
        window.clearTimeout(this.navigationTimer);
        this.navigateToMaintenanceLog();
    }

    navigateToMaintenanceLog() {
        if (!this.maintenanceLogId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.maintenanceLogId, objectApiName: 'Maintenance_Log__c', actionName: 'view' }
        });

        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleClose() { this.dispatchEvent(new CloseActionScreenEvent()); }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Something went wrong. Please try again.';
    }

    get showForm() {
        return !this.isLoading && !this.isInitialError && !this.isSuccess && !this.isSubmitError;
    }

    get machineDetails() {
        return [this.context.manufacturer, this.context.model].filter(Boolean).join(' • ');
    }

    get currentLaborLabel() {
        const labor = this.context.currentLaborHours;
        return `${labor === null || labor === undefined ? 0 : labor} hrs`;
    }
}