import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getReportIssueData from '@salesforce/apex/CustomerReportAnIssueController.getReportIssueData';
import submitServiceRequest from '@salesforce/apex/CustomerReportAnIssueController.submitServiceRequest';
import MACHINE_MEDIA from '@salesforce/resourceUrl/MillTrack_Machine_Media';

export default class CustomerReportAnIssue extends NavigationMixin(LightningElement) {
    machines = [];
    priorities = [];
    isLoading = true;
    isSubmitting = false;
    loadError;
    stepError;
    submissionError;
    currentStep = 1;
    selectedAssetId;
    subject = '';
    description = '';
    errorCode = '';
    priority = 'Medium';
    submissionResult;

    connectedCallback() {
        this.loadData();
    }

    // =========================================================
    // Load
    // =========================================================

    async loadData() {
        this.isLoading = true;
        this.loadError = undefined;

        try {
            const data = await getReportIssueData();
            this.priority = data?.defaultPriority || 'Medium';

            this.machines = (data?.machines || []).map(machine => ({
                ...machine,
                serialDisplay: machine.serialNumber || 'Not available',
                statusDisplay: machine.status || 'Status unavailable',
                manufacturerModelDisplay: this.getManufacturerModelDisplay(machine),
                statusClass: this.getMachineStatusClass(machine.status),
                imageUrl: this.buildStaticResourceUrl(MACHINE_MEDIA, machine.portalImagePath),
                hasImage: !!machine.portalImagePath?.trim(),
                cardClass: 'machine-card',
                selected: false
            }));

            this.priorities = (data?.priorities || []).map(option => ({
                ...option,
                choiceClass: this.getPriorityChoiceClass(option.value, this.priority),
                ariaChecked: option.value === this.priority ? 'true' : 'false'
            }));
        } catch (error) {
            this.loadError = this.getErrorMessage(
                error,
                'Your MillTrack service request form could not be loaded.'
            );
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================
    // General State
    // =========================================================

    get hasLoadError() {
        return !!this.loadError;
    }

    get hasMachines() {
        return this.machines.length > 0;
    }

    get hasSubmitted() {
        return this.submissionResult?.success === true;
    }

    get hasStepError() {
        return !!this.stepError;
    }

    get hasSubmissionError() {
        return !!this.submissionError;
    }

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get isStepThree() {
        return this.currentStep === 3;
    }

    // =========================================================
    // Progress
    // =========================================================

    get stepOneClass() {
        return this.currentStep === 1
            ? 'progress-step active'
            : 'progress-step complete';
    }

    get stepTwoClass() {
        if (this.currentStep === 2) return 'progress-step active';

        return this.currentStep > 2
            ? 'progress-step complete'
            : 'progress-step';
    }

    get stepThreeClass() {
        return this.currentStep === 3
            ? 'progress-step active'
            : 'progress-step';
    }

    get stepOneMarker() {
        return this.currentStep > 1
            ? '✓'
            : '1';
    }

    get stepTwoMarker() {
        return this.currentStep > 2
            ? '✓'
            : '2';
    }

    // =========================================================
    // Review State
    // =========================================================

    get selectedMachine() {
        return this.machines.find(
            machine => machine.id === this.selectedAssetId
        );
    }

    get subjectDisplay() {
        return this.subject?.trim() || '';
    }

    get errorCodeDisplay() {
        return this.errorCode?.trim() || 'Not provided';
    }

    get priorityPillClass() {
        switch (this.priority) {
            case 'Critical':
                return 'priority-pill priority-critical';

            case 'High':
                return 'priority-pill priority-high';

            case 'Medium':
                return 'priority-pill priority-medium';

            case 'Low':
                return 'priority-pill priority-low';

            default:
                return 'priority-pill priority-medium';
        }
    }

    get submitButtonLabel() {
        return this.isSubmitting
            ? 'Submitting...'
            : 'Submit Service Request';
    }

    get isSubmitDisabled() {
        return this.isSubmitting;
    }

    get successCaseNumber() {
        return this.submissionResult?.caseNumber || '';
    }

    // =========================================================
    // Machine Formatting
    // =========================================================

    getManufacturerModelDisplay(machine) {
        const manufacturer = machine?.manufacturer;
        const model = machine?.model;
        const label = [manufacturer, model].filter(Boolean).join(' ');

        return label || machine?.name || 'Machine';
    }

    getMachineStatusClass(status) {
        switch (status) {
            case 'Active':
                return 'status-pill status-green';

            case 'Needs Service':
                return 'status-pill status-orange';

            case 'Temporary Fix Applied':
                return 'status-pill status-tan';

            case 'Out of Service':
                return 'status-pill status-red';

            case 'Retired':
                return 'status-pill status-gray';

            default:
                return 'status-pill status-blue';
        }
    }

    buildStaticResourceUrl(baseUrl, relativePath) {
        if (!baseUrl || !relativePath) return null;

        const normalizedPath = relativePath
            .replace(/^\/+/, '')
            .trim();

        return `${baseUrl}/${normalizedPath}`;
    }

    // =========================================================
    // Priority
    // =========================================================

    getPriorityChoiceClass(value, selectedValue) {
        const classes = ['priority-choice'];

        switch (value) {
            case 'Critical':
                classes.push('priority-choice-critical');
                break;

            case 'High':
                classes.push('priority-choice-high');
                break;

            case 'Medium':
                classes.push('priority-choice-medium');
                break;

            case 'Low':
                classes.push('priority-choice-low');
                break;

            default:
                classes.push('priority-choice-neutral');
        }

        if (value === selectedValue) {
            classes.push('selected');
        }

        return classes.join(' ');
    }

    // =========================================================
    // Machine Selection
    // =========================================================

    handleMachineSelect(event) {
        this.selectMachine(event.currentTarget.dataset.id);
    }

    handleMachineKeydown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') return;

        event.preventDefault();
        this.selectMachine(event.currentTarget.dataset.id);
    }

    selectMachine(assetId) {
        if (!assetId) return;

        this.selectedAssetId = assetId;
        this.stepError = undefined;

        this.machines = this.machines.map(machine => {
            const selected = machine.id === this.selectedAssetId;

            return {
                ...machine,
                selected,
                cardClass: selected
                    ? 'machine-card selected'
                    : 'machine-card'
            };
        });
    }

    // =========================================================
    // Form
    // =========================================================

    handleSubjectChange(event) {
        this.subject = event.target.value || '';
        this.stepError = undefined;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value || '';
        this.stepError = undefined;
    }

    handleErrorCodeChange(event) {
        this.errorCode = event.target.value || '';
        this.stepError = undefined;
    }

    handlePrioritySelect(event) {
        this.priority = event.currentTarget.dataset.value;
        this.stepError = undefined;

        this.priorities = this.priorities.map(option => ({
            ...option,
            choiceClass: this.getPriorityChoiceClass(
                option.value,
                this.priority
            ),
            ariaChecked: option.value === this.priority
                ? 'true'
                : 'false'
        }));
    }

    // =========================================================
    // Wizard Navigation
    // =========================================================

    handleContinueFromMachine() {
        if (!this.selectedAssetId) {
            this.stepError = 'Please select the machine experiencing the issue.';
            return;
        }

        this.stepError = undefined;
        this.currentStep = 2;
        this.scrollToWizardTop();
    }

    handleContinueToReview() {
        if (!this.subject?.trim()) {
            this.stepError = 'Please enter a subject for your service request.';
            return;
        }

        if (!this.description?.trim()) {
            this.stepError = 'Please describe the problem you are experiencing.';
            return;
        }

        if (this.subject.trim().length > 255) {
            this.stepError = 'Subject cannot exceed 255 characters.';
            return;
        }

        this.stepError = undefined;
        this.currentStep = 3;
        this.scrollToWizardTop();
    }

    handleBack() {
        this.stepError = undefined;
        this.currentStep = Math.max(
            1,
            this.currentStep - 1
        );

        this.scrollToWizardTop();
    }

    handleEditMachine() {
        this.stepError = undefined;
        this.currentStep = 1;
        this.scrollToWizardTop();
    }

    handleEditDetails() {
        this.stepError = undefined;
        this.currentStep = 2;
        this.scrollToWizardTop();
    }

    // =========================================================
    // Submit
    // =========================================================

    async handleSubmit() {
        if (
            this.isSubmitting ||
            !this.selectedAssetId ||
            !this.subject?.trim() ||
            !this.description?.trim()
        ) {
            return;
        }

        this.isSubmitting = true;
        this.submissionError = undefined;

        try {
            const result = await submitServiceRequest({
                assetId: this.selectedAssetId,
                subject: this.normalizeText(this.subject),
                description: this.description.trim(),
                errorCode: this.normalizeText(this.errorCode),
                priority: this.priority,
                technicianRequested: false
            });

            if (!result?.success) {
                this.submissionError =
                    result?.message ||
                    'We could not create your service request. Please try again.';

                return;
            }

            this.submissionResult = result;

            requestAnimationFrame(() => {
                this.scrollToComponentTop();
            });
        } catch (error) {
            this.submissionError = this.getErrorMessage(
                error,
                'We could not submit your service request. Please try again.'
            );
        } finally {
            this.isSubmitting = false;
        }
    }

    // =========================================================
    // Navigation
    // =========================================================

    handleViewServiceRequest() {
        const caseId = this.submissionResult?.caseId;

        if (!caseId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    async handleBackHome() {
        try {
            const homeUrl = await this[
                NavigationMixin.GenerateUrl
            ]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home'
                }
            });

            window.location.assign(homeUrl);
        } catch (error) {
            this[
                NavigationMixin.Navigate
            ]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home'
                }
            });
        }
    }

    handleRetryLoad() {
        this.loadData();
    }

    // =========================================================
    // Helpers
    // =========================================================

    normalizeText(value) {
        const normalized = value?.trim();
        return normalized || null;
    }

    scrollToWizardTop() {
        requestAnimationFrame(() => {
            const wizard = this.template.querySelector(
                '.wizard-shell'
            );

            if (wizard) {
                wizard.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    }

    scrollToComponentTop() {
        const shell = this.template.querySelector(
            '.report-shell'
        );

        if (shell) {
            shell.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    }

    getErrorMessage(error, fallbackMessage) {
        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return fallbackMessage;
    }
}