import { LightningElement, api } from 'lwc';
import getRequestContext from '@salesforce/apex/TechnicianRequestPartsController.getRequestContext';
import getManufacturerParts from '@salesforce/apex/TechnicianRequestPartsController.getManufacturerParts';
import submitPartsRequestV2 from '@salesforce/apex/TechnicianRequestPartsController.submitPartsRequestV2';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class TechnicianRequestPartsWizard extends NavigationMixin(LightningElement) {
    _recordId;
    hasLoaded = false;

    context = {};
    catalogParts = [];
    selectedParts = [];

    currentStep = 1;
    visibleCount = 12;

    searchTerm = '';
    requestReason = '';
    visitSummary = '';
    laborHours;
    temporaryRepairApplied = false;

    isLoading = true;
    isSearching = false;
    isSubmitting = false;
    isSuccess = false;
    isInitialError = false;
    isSubmitError = false;

    stepError;
    errorMessage;
    notificationWarning;
    maintenanceLogId;
    requestedPartCount = 0;

    searchTimer;
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
        window.clearTimeout(this.searchTimer);
        window.clearTimeout(this.navigationTimer);
    }

    async initialize() {
        this.isLoading = true;

        try {
            this.context = await getRequestContext({ workOrderId: this.recordId });
            await this.loadParts('');
        } catch (error) {
            this.isInitialError = true;
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadParts(searchTerm) {
        this.isSearching = true;
        this.stepError = null;

        try {
            this.catalogParts = await getManufacturerParts({
                workOrderId: this.recordId,
                searchTerm
            }) || [];
        } catch (error) {
            this.catalogParts = [];
            this.stepError = this.getErrorMessage(error);
        } finally {
            this.isSearching = false;
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.visibleCount = 12;
        this.stepError = null;

        window.clearTimeout(this.searchTimer);
        this.searchTimer = window.setTimeout(
            () => this.loadParts(this.searchTerm),
            300
        );
    }

    handlePartSelect(event) {
        const id = event.currentTarget.dataset.id;
        const catalogPart = this.catalogParts.find(part => part.id === id);
        if (!catalogPart) return;

        const existingIndex = this.selectedParts.findIndex(part => part.id === id);

        if (existingIndex >= 0) {
            this.selectedParts = this.selectedParts.filter(part => part.id !== id);
        } else {
            this.selectedParts = [
                ...this.selectedParts,
                {
                    ...catalogPart,
                    quantity: 1
                }
            ];
        }

        this.stepError = null;
    }

    handleRemovePart(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedParts = this.selectedParts.filter(part => part.id !== id);
        this.stepError = null;
    }

    handleQuantityChange(event) {
        const id = event.target.dataset.id;
        const quantity = Number(event.target.value);

        this.selectedParts = this.selectedParts.map(part =>
            part.id === id
                ? { ...part, quantity }
                : part
        );

        this.stepError = null;
    }

    handleShowMore() {
        this.visibleCount += 12;
    }

    handleShowLess() {
        this.visibleCount = 12;
    }

    handleReasonChange(event) {
        this.requestReason = event.target.value;
        this.stepError = null;
    }

    handleSummaryChange(event) {
        this.visitSummary = event.target.value;
        this.stepError = null;
    }

    handleLaborChange(event) {
        this.laborHours = event.target.value;
        this.stepError = null;
    }

    handleTemporaryRepairChange(event) {
        this.temporaryRepairApplied = event.target.checked;
    }

    handleNext() {
        this.stepError = null;

        if (!this.selectedParts.length) {
            this.stepError = 'Select at least one required part.';
            return;
        }

        const invalidQuantity = this.selectedParts.some(
            part => !Number.isInteger(Number(part.quantity)) || Number(part.quantity) <= 0
        );

        if (invalidQuantity) {
            this.stepError = 'Each selected part must have a whole-number quantity greater than zero.';
            return;
        }

        if (!this.requestReason?.trim()) {
            this.stepError = 'Enter a reason for the parts request.';
            return;
        }

        this.currentStep = 2;
    }

    handleBack() {
        if (this.isSubmitting) return;
        this.stepError = null;
        this.currentStep = 1;
    }

    async handleSubmit() {
        this.stepError = null;

        const inputs = [...this.template.querySelectorAll('.step-two-input')];
        const valid = inputs.reduce((result, input) => {
            input.reportValidity();
            return input.checkValidity() && result;
        }, true);

        if (!valid) return;

        if (!this.visitSummary?.trim()) {
            this.stepError = 'Enter a summary of the service visit.';
            return;
        }

        const labor = Number(this.laborHours);

        if (Number.isNaN(labor) || labor < 0) {
            this.stepError = 'Enter valid labor hours.';
            return;
        }

        const parts = this.selectedParts.map(part => ({
            partCatalogId: part.id,
            quantity: Number(part.quantity)
        }));

        this.isSubmitting = true;

        try {
            const result = await submitPartsRequestV2({
                workOrderId: this.recordId,
                parts,
                requestReason: this.requestReason.trim(),
                visitSummary: this.visitSummary.trim(),
                laborHours: labor,
                temporaryRepairApplied: this.temporaryRepairApplied
            });

            this.maintenanceLogId = result.maintenanceLogId;
            this.requestedPartCount = result.requestedPartCount || parts.length;
            this.notificationWarning = result.notificationWarning;
            this.isSuccess = true;

            /*
             * IMPORTANT:
             * Do NOT refresh the Work Order here.
             * Request Parts intentionally transfers ownership back to the
             * Service Manager Queue, so the technician may immediately lose
             * access to the parent Work Order.
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

    handleReturnToWizard() {
        this.isSubmitError = false;
        this.errorMessage = null;
        this.currentStep = 2;
    }

    handleOpenMaintenanceLog() {
        window.clearTimeout(this.navigationTimer);
        this.navigateToMaintenanceLog();
    }

    navigateToMaintenanceLog() {
        if (!this.maintenanceLogId) return;

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

    get showWizard() {
        return !this.isLoading &&
            !this.isInitialError &&
            !this.isSuccess &&
            !this.isSubmitError;
    }

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get displayedParts() {
        const selectedIds = new Set(this.selectedParts.map(part => part.id));

        return this.catalogParts.slice(0, this.visibleCount).map(part => ({
            ...part,
            selected: selectedIds.has(part.id),
            cssClass: selectedIds.has(part.id)
                ? 'catalog-row selected'
                : 'catalog-row'
        }));
    }

    get hasParts() {
        return !this.isSearching && this.catalogParts.length > 0;
    }

    get showNoParts() {
        return !this.isSearching && this.catalogParts.length === 0;
    }

    get hasSelectedParts() {
        return this.selectedParts.length > 0;
    }

    get hasMoreParts() {
        return this.visibleCount < this.catalogParts.length;
    }

    get canShowLess() {
        return this.visibleCount > 12;
    }

    get selectedCountLabel() {
        const count = this.selectedParts.length;
        return count === 1 ? '1 selected part' : `${count} selected parts`;
    }

    get manufacturerLabel() {
        return this.context.manufacturer
            ? `${this.context.manufacturer} Part Catalog`
            : 'Part Catalog';
    }

    get machineDetails() {
        return [this.context.manufacturer, this.context.model]
            .filter(Boolean)
            .join(' • ');
    }

    get successMessage() {
        const count = this.requestedPartCount || this.selectedParts.length;
        return count === 1
            ? '1 requested part and this service visit have been recorded.'
            : `${count} requested parts and this service visit have been recorded.`;
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
}