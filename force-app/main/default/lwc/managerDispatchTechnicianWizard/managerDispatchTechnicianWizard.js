import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getDispatchContext from '@salesforce/apex/ManagerDispatchTechnicianController.getDispatchContext';
import dispatchTechnician from '@salesforce/apex/ManagerDispatchTechnicianController.dispatchTechnician';

export default class ManagerDispatchTechnicianWizard extends LightningElement {

    @api recordId;

    context;
    parts = [];
    technicians = [];
    saveResult;

    currentStep = 1;

    selectedTechnicianId = '';
    scheduledDate = '';
    scheduledTime = '';
    readyConfirmed = false;

    isLoading = true;
    isSaving = false;
    showSuccessConfirmation = false;

    errorMessage = '';
    saveErrorMessage = '';

    // =========================================================
    // INITIAL LOAD
    // =========================================================

    async connectedCallback() {
        await this.loadDispatchContext();
    }

    async loadDispatchContext() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            this.context = await getDispatchContext({ workOrderId: this.recordId });

            if (!this.context?.eligible) {
                this.errorMessage = this.context?.ineligibleReason || 'This Work Order is not available for technician dispatch.';
                return;
            }

            this.parts = (this.context?.parts || []).map((part, index) => ({ ...part, rowNumber: index + 1 }));
            this.technicians = this.context?.technicians || [];

            this.selectedTechnicianId = this.context?.suggestedTechnicianId || '';
            if (this.context?.scheduledVisit) {
                const visit = new Date(this.context.scheduledVisit);

                if (!Number.isNaN(visit.getTime())) {
                    this.scheduledDate = `${visit.getFullYear()}-${String(visit.getMonth() + 1).padStart(2, '0')}-${String(visit.getDate()).padStart(2, '0')}`;
                    this.scheduledTime = `${String(visit.getHours()).padStart(2, '0')}:${String(visit.getMinutes()).padStart(2, '0')}`;
                }
            }

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

    get priority() {
        return this.context?.priority || 'Not Set';
    }

    get problemSummary() {
        return this.context?.problemSummary || 'No problem summary is available.';
    }

    get recommendedFixSummary() {
        return this.context?.recommendedFixSummary || 'No approved repair summary is available.';
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
        return this.currentStep === 1 ? 'progress-step active' : 'progress-step complete';
    }

    get stepTwoClass() {
        return this.currentStep === 2 ? 'progress-step active' : 'progress-step';
    }

    // =========================================================
    // PARTS
    // =========================================================

    get hasParts() {
        return this.parts.length > 0;
    }

    get partCountLabel() {
        const count = this.parts.length;
        return count === 1 ? '1 required part' : `${count} required parts`;
    }

    get displayParts() {
        return this.parts.map(part => ({
            ...part,
            statusClass: this.getPartStatusClass(part.status)
        }));
    }

    get blockingParts() {
        return this.parts.filter(part => ['Requested', 'Ordered', 'Shipped'].includes(part.status));
    }

    get hasBlockingParts() {
        return this.blockingParts.length > 0;
    }

    get blockingPartMessage() {
        const count = this.blockingParts.length;

        if (count === 1) {
            return '1 required part is still outstanding. Receive the part before dispatching a technician.';
        }

        return `${count} required parts are still outstanding. Receive those parts before dispatching a technician.`;
    }

    getPartStatusClass(status) {
        if (status === 'Received' || status === 'Installed') return 'part-status part-status-ready';
        if (status === 'Cancelled') return 'part-status part-status-cancelled';
        return 'part-status part-status-outstanding';
    }

    // =========================================================
    // TECHNICIAN / SCHEDULE
    // =========================================================

    get technicianOptions() {
        return this.technicians.map(technician => ({ label: technician.name, value: technician.id }));
    }

    get hasTechnicians() {
        return this.technicians.length > 0;
    }

    get selectedTechnicianName() {
        const technician = this.technicians.find(item => item.id === this.selectedTechnicianId);
        return technician?.name || 'No technician selected';
    }

    get scheduledVisit() {
        if (!this.scheduledDate || !this.scheduledTime) return '';

        const visit = new Date(`${this.scheduledDate}T${this.scheduledTime}`);
        return Number.isNaN(visit.getTime()) ? '' : visit.toISOString();
    }

    get scheduledVisitInPast() {
        if (!this.scheduledVisit) return false;
        return new Date(this.scheduledVisit).getTime() < Date.now();
    }

    get scheduledVisitDisplay() {
        if (!this.scheduledVisit) return 'No visit scheduled';

        const value = new Date(this.scheduledVisit);

        if (Number.isNaN(value.getTime())) return this.scheduledVisit;

        return new Intl.DateTimeFormat('en-CA', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(value);
    }

    get isContinueDisabled() {
        return this.isSaving || !this.hasTechnicians || !this.selectedTechnicianId ||
            !this.scheduledDate || !this.scheduledTime || this.scheduledVisitInPast ||
            !this.readyConfirmed || this.hasBlockingParts;
    }

    handleTechnicianChange(event) {
        this.selectedTechnicianId = event.detail.value;
        this.saveErrorMessage = '';
    }

    handleScheduledDateChange(event) {
        this.scheduledDate = event.target.value;
        this.saveErrorMessage = '';
    }

    handleScheduledTimeChange(event) {
        this.scheduledTime = event.target.value;
        this.saveErrorMessage = '';
    }

    handleReadyChange(event) {
        this.readyConfirmed = event.target.checked;
        this.saveErrorMessage = '';
    }

    // =========================================================
    // NAVIGATION
    // =========================================================

    handleContinue() {
        if (this.isContinueDisabled) return;

        this.saveErrorMessage = '';
        this.currentStep = 2;
    }

    handleBack() {
        if (this.isSaving) return;

        this.saveErrorMessage = '';
        if (this.currentStep === 2) this.currentStep = 1;
    }

    handleCancel() {
        if (this.isSaving || this.showSuccessConfirmation) return;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // =========================================================
    // STEP 2
    // =========================================================

    get isDispatchDisabled() {
        return this.isSaving || !this.recordId || !this.selectedTechnicianId ||
            !this.scheduledDate || !this.scheduledTime || this.scheduledVisitInPast ||
            !this.readyConfirmed || this.hasBlockingParts;
    }

    // =========================================================
    // SAVE
    // =========================================================

    async handleDispatch() {
        if (this.isDispatchDisabled) return;

        this.isSaving = true;
        this.saveErrorMessage = '';

        try {
            this.saveResult = await dispatchTechnician({
                workOrderId: this.recordId,
                technicianId: this.selectedTechnicianId,
                scheduledVisit: this.scheduledVisit
            });

            this.showSuccessConfirmation = true;

        } catch (error) {
            this.saveErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Unable to Dispatch Technician',
                message: this.saveErrorMessage,
                variant: 'error'
            }));

        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================
    // SUCCESS
    // =========================================================

    get successHeading() {
        return 'Technician Dispatched';
    }

    get successMessage() {
        const technicianName = this.saveResult?.technicianName || this.selectedTechnicianName;
        return `${this.workOrderNumber} has been assigned to ${technicianName} for ${this.scheduledVisitDisplay}.`;
    }

    get successWorkOrderStatus() {
        return this.saveResult?.workOrderStatus || 'Assigned';
    }

    get successCaseStatus() {
        return this.saveResult?.caseStatus || 'Scheduled';
    }

    get successNextStepMessage() {
        const technicianName = this.saveResult?.technicianName || this.selectedTechnicianName;
        return `The Work Order is now available in ${technicianName}'s assigned service work. ${technicianName} will visit ${this.accountName} on ${this.scheduledVisitDisplay} to perform the approved repair.`;
    }
    handleSuccessClose() {
        const result = this.saveResult || {};

        this.dispatchEvent(new CustomEvent('complete', {
            detail: {
                workOrderId: result.workOrderId || this.recordId,
                workOrderNumber: result.workOrderNumber,
                workOrderStatus: result.workOrderStatus,
                caseStatus: result.caseStatus,
                assetStatus: result.assetStatus,
                technicianId: result.technicianId || this.selectedTechnicianId,
                technicianName: result.technicianName || this.selectedTechnicianName,
                scheduledVisit: result.scheduledVisit || this.scheduledVisit
            }
        }));
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