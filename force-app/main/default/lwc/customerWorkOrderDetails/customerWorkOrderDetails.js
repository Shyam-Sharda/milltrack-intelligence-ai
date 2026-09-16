import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getWorkOrderDetails from '@salesforce/apex/CustomerWorkOrderDetailsController.getWorkOrderDetails';
import MACHINE_MEDIA from '@salesforce/resourceUrl/MillTrack_Machine_Media';

export default class CustomerWorkOrderDetails extends NavigationMixin(LightningElement) {
    _recordId;

    isLoading = true;
    errorMessage;

    serviceVisit;
    progress;
    machine;
    serviceRequest;


    // =========================================================
    // Record ID
    // =========================================================

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (!value || value === this._recordId) {
            return;
        }

        this._recordId = value;
        this.loadWorkOrderDetails();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        if (this._recordId || !pageReference) {
            return;
        }

        const pageRecordId = pageReference?.attributes?.recordId || pageReference?.state?.recordId;

        if (pageRecordId) {
            this._recordId = pageRecordId;
            this.loadWorkOrderDetails();
        }
    }


    // =========================================================
    // Load Data
    // =========================================================

    async loadWorkOrderDetails() {
        if (!this._recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getWorkOrderDetails({ workOrderId: this._recordId });

            this.progress = data?.progress ? this.prepareProgress(data.progress) : undefined;
            this.serviceVisit = data?.serviceVisit ? this.prepareServiceVisit(data.serviceVisit) : undefined;
            this.machine = data?.machine ? this.prepareMachine(data.machine) : undefined;
            this.serviceRequest = data?.serviceRequest
                ? this.prepareServiceRequest(data.serviceRequest)
                : undefined;
        } catch (error) {
            this.serviceVisit = undefined;
            this.progress = undefined;
            this.machine = undefined;
            this.serviceRequest = undefined;
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    @api
    async refresh() {
        await this.loadWorkOrderDetails();
    }


    // =========================================================
    // Service Visit
    // =========================================================

    prepareServiceVisit(serviceVisit) {
        return {
            ...serviceVisit,
            displayNumber: serviceVisit.workOrderNumber ? `#${serviceVisit.workOrderNumber}` : '',
            subjectDisplay: serviceVisit.subject || 'MillTrack service visit',

            recommendedSolutionDisplay:
                serviceVisit.recommendedSolution ||
                'MillTrack AI is still preparing a recommended solution for this service visit.',

            assignedTechnicianDisplay: this.getAssignedTechnicianDisplay(
                serviceVisit.assignedTechnicianName,
                serviceVisit.dispatchStatus
            )
        };
    }

    getAssignedTechnicianDisplay(assignedTechnicianName, dispatchStatus) {
        if (assignedTechnicianName) {
            return assignedTechnicianName;
        }

        const technicianAssignedStatuses = [
            'Assigned',
            'In Progress',
            'Temporary Fix',
            'Completed'
        ];

        return technicianAssignedStatuses.includes(dispatchStatus)
            ? 'Technician assigned'
            : 'To be assigned';
    }


    // =========================================================
    // Progress
    // =========================================================

    prepareProgress(progress) {
        const stages = Array.isArray(progress.stages) ? progress.stages : [];

        return {
            ...progress,

            statusClass: this.getProgressStatusClass(
                progress.currentStage,
                progress.isCancelled
            ),

            stages: stages.map((stage, index) => {
                const state = stage.state || 'upcoming';

                return {
                    ...stage,
                    stepNumber: index + 1,
                    itemClass: `progress-step progress-step-${state}`,
                    markerClass: `progress-marker progress-marker-${state}`,
                    ariaCurrent: state === 'current' ? 'step' : null
                };
            })
        };
    }


    // =========================================================
    // Machine
    // =========================================================

    prepareMachine(machine) {
        return {
            ...machine,

            imageUrl: this.buildStaticResourceUrl(
                MACHINE_MEDIA,
                machine.portalImagePath
            ),

            manufacturerDisplay: machine.manufacturer || 'Not recorded',
            modelDisplay: machine.model || 'Not recorded',
            serialNumberDisplay: machine.serialNumber || 'Not recorded',
            statusDisplay: machine.status || 'Status unavailable',
            statusClass: this.getMachineStatusClass(machine.status)
        };
    }


    // =========================================================
    // Related Service Request
    // =========================================================

    prepareServiceRequest(serviceRequest) {
        return {
            ...serviceRequest,

            displayNumber: serviceRequest.caseNumber
                ? `#${serviceRequest.caseNumber}`
                : '',

            subjectDisplay: serviceRequest.subject || 'Service request',

            customerStatusDisplay:
                serviceRequest.customerStatus ||
                'Request Received',

            priorityDisplay:
                serviceRequest.priority ||
                'Not specified',

            statusClass:
                this.getCaseStatusClass(
                    serviceRequest.customerStatus
                ),

            priorityClass:
                this.getPriorityClass(
                    serviceRequest.priority
                )
        };
    }


    // =========================================================
    // What Happens Next
    // =========================================================

    get nextStep() {
        const dispatchStatus = this.serviceVisit?.dispatchStatus;

        switch (dispatchStatus) {
            case 'Pending':
                return {
                    title: 'MillTrack is reviewing your service visit',
                    message:
                        'The service team is reviewing the reported issue and determining the appropriate service response.'
                };

            case 'Parts to Order':
                return {
                    title: 'Required parts are being arranged',
                    message:
                        'MillTrack is identifying and coordinating the parts needed before this service visit can move forward.'
                };

            case 'Waiting on Parts':
                return {
                    title: 'Your service visit is waiting on parts',
                    message:
                        'The required parts are being coordinated. Service will continue once those parts are available.'
                };

            case 'Ready_to_Assign':
                return {
                    title: 'Your visit is ready for technician assignment',
                    message:
                        'MillTrack has reviewed the service requirements and is preparing to assign the appropriate technician.'
                };

            case 'Assigned':
                return {
                    title: 'A technician has been assigned',
                    message:
                        'Your service visit is moving into the scheduled service stage. Review the visit details above for the latest schedule information.'
                };

            case 'In Progress':
                return {
                    title: 'Service is currently in progress',
                    message:
                        'Your technician is actively working through the reported machine issue. Service information will continue to update as work progresses.'
                };

            case 'Temporary Fix':
                return {
                    title: 'A temporary repair has been completed',
                    message:
                        'The machine has received a temporary repair. Additional follow-up service is still required before the visit is fully completed.'
                };

            case 'Completed':
                return {
                    title: 'Your service visit has been completed',
                    message:
                        'The service work has been completed. Review the service information and related request for the final visit context.'
                };

            case 'Cancelled':
                return {
                    title: 'This service visit is no longer active',
                    message:
                        'This service visit has been cancelled. If the machine still requires assistance, contact MillTrack or submit another service request.'
                };

            default:
                return {
                    title: 'MillTrack is reviewing your service visit',
                    message:
                        'Your service visit is active and the MillTrack team is coordinating the appropriate next action.'
                };
        }
    }


    // =========================================================
    // State Getters
    // =========================================================

    get hasData() {
        return Boolean(
            !this.isLoading &&
            !this.errorMessage &&
            this.serviceVisit
        );
    }

    get hasProgress() {
        return Boolean(this.progress);
    }

    get showProgressTracker() {
        return Boolean(
            this.progress &&
            !this.progress.isCancelled
        );
    }

    get showCancelledProgress() {
        return Boolean(
            this.progress?.isCancelled
        );
    }

    get hasMachine() {
        return Boolean(this.machine);
    }

    get hasMachineImage() {
        return Boolean(this.machine?.imageUrl);
    }

    get hasServiceRequest() {
        return Boolean(this.serviceRequest);
    }

    get hasScheduledVisit() {
        return Boolean(this.serviceVisit?.scheduledVisit);
    }

    get hasWorkStarted() {
        return Boolean(this.serviceVisit?.workStartedDateTime);
    }

    get hasWorkEnded() {
        return Boolean(this.serviceVisit?.workEndedDateTime);
    }


    // =========================================================
    // Navigation
    // =========================================================

    handleViewMachine() {
        if (!this.machine?.id) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.machine.id,
                objectApiName: 'Asset',
                actionName: 'view'
            }
        });
    }

    handleViewServiceRequest() {
        if (!this.serviceRequest?.id) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.serviceRequest.id,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }


    // =========================================================
    // Status Classes
    // =========================================================

    getProgressStatusClass(status, isCancelled) {
        if (isCancelled) {
            return 'status-badge status-badge-danger';
        }

        const normalized = (status || '').toLowerCase();

        if (normalized.includes('completed')) {
            return 'status-badge status-badge-success';
        }

        if (
            normalized.includes('waiting') ||
            normalized.includes('review')
        ) {
            return 'status-badge status-badge-warning';
        }

        if (
            normalized.includes('scheduled') ||
            normalized.includes('progress') ||
            normalized.includes('assigned')
        ) {
            return 'status-badge status-badge-info';
        }

        return 'status-badge status-badge-primary';
    }

    getCaseStatusClass(status) {
        const normalized = (status || '').toLowerCase();

        if (normalized.includes('complete')) {
            return 'status-badge status-badge-success';
        }

        if (
            normalized.includes('waiting') ||
            normalized.includes('follow-up')
        ) {
            return 'status-badge status-badge-warning';
        }

        if (
            normalized.includes('progress') ||
            normalized.includes('scheduled')
        ) {
            return 'status-badge status-badge-info';
        }

        return 'status-badge status-badge-primary';
    }

    getPriorityClass(priority) {
        switch ((priority || '').toLowerCase()) {
            case 'critical':
                return 'priority-badge priority-critical';

            case 'high':
                return 'priority-badge priority-high';

            case 'medium':
                return 'priority-badge priority-medium';

            case 'low':
                return 'priority-badge priority-low';

            default:
                return 'priority-badge';
        }
    }

    getMachineStatusClass(status) {
        const normalized = (status || '').toLowerCase();

        if (
            normalized.includes('needs service') ||
            normalized.includes('out of service')
        ) {
            return 'machine-status machine-status-warning';
        }

        if (normalized.includes('temporary fix')) {
            return 'machine-status machine-status-info';
        }

        if (normalized.includes('active')) {
            return 'machine-status machine-status-success';
        }

        return 'machine-status';
    }


    // =========================================================
    // Static Resource
    // =========================================================

    buildStaticResourceUrl(baseUrl, relativePath) {
        if (!baseUrl || !relativePath) {
            return null;
        }

        const normalizedPath = relativePath
            .replace(/^\/+/, '')
            .trim();

        const encodedPath = normalizedPath
            .split('/')
            .map((segment) => encodeURIComponent(segment))
            .join('/');

        return `${baseUrl}/${encodedPath}`;
    }


    // =========================================================
    // Error Handling
    // =========================================================

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'Your service visit could not be loaded. Please refresh the page and try again.';
    }
}