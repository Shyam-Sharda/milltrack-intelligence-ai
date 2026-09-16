import { LightningElement, api } from 'lwc';
import getTemporaryFixContext from '@salesforce/apex/TechnicianTemporaryFixController.getTemporaryFixContext';
import submitTemporaryFix from '@salesforce/apex/TechnicianTemporaryFixController.submitTemporaryFix';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class TechnicianTemporaryFixWizard extends NavigationMixin(LightningElement) {
    _recordId;
    hasLoaded = false;

    context = {};

    visitSummary = '';
    laborHours;

    isLoading = true;
    isSubmitting = false;
    isSuccess = false;
    isInitialError = false;
    isSubmitError = false;

    inlineError;
    errorMessage;
    notificationWarning;
    maintenanceLogId;

    navigationTimer;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;

        if (value && !this.hasLoaded) {
            this.hasLoaded = true;
            this.initialize();
        }
    }

    disconnectedCallback() {
        window.clearTimeout(this.navigationTimer);
    }

    async initialize() {
        this.isLoading = true;

        try {
            this.context = await getTemporaryFixContext({
                workOrderId: this.recordId
            });
        } catch (error) {
            this.isInitialError = true;
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleSummaryChange(event) {
        this.visitSummary = event.target.value;
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

        if (!valid) {
            return;
        }

        if (!this.visitSummary?.trim()) {
            this.inlineError = 'Enter a summary of the service visit.';
            return;
        }

        const labor = Number(this.laborHours);

        if (Number.isNaN(labor) || labor <= 0) {
            this.inlineError = 'Labor Hours must be greater than 0.';
            return;
        }

        this.isSubmitting = true;

        try {
            const result = await submitTemporaryFix({
                workOrderId: this.recordId,
                visitSummary: this.visitSummary.trim(),
                laborHours: labor
            });

            this.maintenanceLogId = result.maintenanceLogId;
            this.notificationWarning = result.warningMessage;
            this.isSuccess = true;

            /*
             * IMPORTANT:
             * Do NOT refresh the Work Order here.
             *
             * Temporary Repair / Follow-Up intentionally transfers ownership
             * back to the Service Manager Queue. The technician may immediately
             * lose access to the parent Work Order.
             *
             * Navigate directly to the newly created Maintenance Log instead.
             */
            this.navigationTimer = window.setTimeout(
                () => this.navigateToMaintenanceLog(),
                this.notificationWarning ? 2500 : 1500
            );

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
        if (!this.maintenanceLogId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.maintenanceLogId,
                objectApiName: 'Maintenance_Log__c',
                actionName: 'view'
            }
        });

        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    getErrorMessage(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Something went wrong. Please try again.'
        );
    }

    get showForm() {
        return !this.isLoading &&
            !this.isInitialError &&
            !this.isSuccess &&
            !this.isSubmitError;
    }

    get machineDetails() {
        return [this.context.manufacturer, this.context.model]
            .filter(Boolean)
            .join(' • ');
    }

    get currentLaborLabel() {
        const labor = this.context.currentLaborHours;

        if (labor === null || labor === undefined) {
            return '0 hrs';
        }

        return `${labor} hrs`;
    }
}