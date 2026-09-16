import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getCaseDetails from '@salesforce/apex/CustomerCaseDetailsController.getCaseDetails';
import MACHINE_MEDIA from '@salesforce/resourceUrl/MillTrack_Machine_Media';

export default class CustomerCaseDetails extends NavigationMixin(LightningElement) {
    _recordId;

    isLoading = true;
    errorMessage;

    serviceRequest;
    machine;
    serviceVisit;


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
        this.loadCaseDetails();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        if (this._recordId || !pageReference) {
            return;
        }

        const pageRecordId =
            pageReference?.attributes?.recordId ||
            pageReference?.state?.recordId;

        if (pageRecordId) {
            this._recordId = pageRecordId;
            this.loadCaseDetails();
        }
    }


    // =========================================================
    // Load Data
    // =========================================================

    async loadCaseDetails() {
        if (!this._recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getCaseDetails({
                caseId: this._recordId
            });

            this.serviceRequest = data?.serviceRequest
                ? this.prepareServiceRequest(data.serviceRequest)
                : undefined;

            this.machine = data?.machine
                ? this.prepareMachine(data.machine)
                : undefined;

            this.serviceVisit = data?.serviceVisit
                ? this.prepareServiceVisit(data.serviceVisit)
                : undefined;

        } catch (error) {
            this.serviceRequest = undefined;
            this.machine = undefined;
            this.serviceVisit = undefined;
            this.errorMessage = this.normalizeError(error);

        } finally {
            this.isLoading = false;
        }
    }


    // =========================================================
    // Service Request
    // =========================================================

    prepareServiceRequest(serviceRequest) {
        const technicianRequested =
            serviceRequest.technicianRequested === true;

        return {
            ...serviceRequest,

            displayNumber:
                serviceRequest.caseNumber
                    ? `#${serviceRequest.caseNumber}`
                    : '',

            statusClass:
                this.getCaseStatusClass(
                    serviceRequest.customerStatus
                ),

            priorityClass:
                this.getPriorityClass(
                    serviceRequest.priority
                ),

            priorityDisplay:
                serviceRequest.priority ||
                'Not specified',

            subjectDisplay:
                serviceRequest.subject ||
                'Service request',

            descriptionDisplay:
                serviceRequest.description ||
                'No additional issue description was provided.',

            errorCodeDisplay:
                serviceRequest.errorCode ||
                'No error code reported',

            technicianRequestedDisplay:
                technicianRequested
                    ? 'Yes — technician requested'
                    : 'No technician specifically requested',

            technicianRequestedClass:
                technicianRequested
                    ? 'detail-value detail-value-accent'
                    : 'detail-value'
        };
    }


    // =========================================================
    // Machine
    // =========================================================

    prepareMachine(machine) {
        return {
            ...machine,

            imageUrl:
                this.buildStaticResourceUrl(
                    MACHINE_MEDIA,
                    machine.portalImagePath
                ),

            manufacturerDisplay:
                machine.manufacturer ||
                'Not recorded',

            modelDisplay:
                machine.model ||
                'Not recorded',

            serialNumberDisplay:
                machine.serialNumber ||
                'Not recorded',

            statusDisplay:
                machine.status ||
                'Status unavailable',

            statusClass:
                this.getMachineStatusClass(
                    machine.status
                )
        };
    }


    // =========================================================
    // Service Visit
    // =========================================================

    prepareServiceVisit(serviceVisit) {
        return {
            ...serviceVisit,

            displayNumber:
                serviceVisit.workOrderNumber
                    ? `#${serviceVisit.workOrderNumber}`
                    : 'Service Visit',

            customerStatusDisplay:
                serviceVisit.customerStatus ||
                'Status unavailable'
        };
    }


    // =========================================================
    // Request Progress
    // =========================================================

    get progressSteps() {
        const currentStatus =
            this.serviceRequest?.customerStatus ||
            'Request Received';

        let activeIndex = 0;
        let isCompleted = false;

        switch (currentStatus) {
            case 'Visit Scheduled':
                activeIndex = 1;
                break;

            case 'Service in Progress':
            case 'Waiting on Parts':
            case 'Follow-Up Required':
                activeIndex = 2;
                break;

            case 'Completed':
                activeIndex = 3;
                isCompleted = true;
                break;

            default:
                activeIndex = 0;
        }

        const steps = [
            {
                label: 'Request Received',
                description:
                    'Your issue has been submitted to MillTrack.'
            },
            {
                label: 'Visit Scheduled',
                description:
                    'A service visit is being prepared or scheduled.'
            },
            {
                label: 'Service in Progress',
                description:
                    'Your machine is actively moving through service.'
            },
            {
                label: 'Completed',
                description:
                    'The service request has been resolved.'
            }
        ];

        return steps.map((step, index) => {
            const isReached =
                isCompleted ||
                index <= activeIndex;

            const isCurrent =
                !isCompleted
                    ? index === activeIndex
                    : index === steps.length - 1;

            return {
                ...step,

                stepNumber:
                    index + 1,

                itemClass:
                    isCurrent
                        ? 'progress-step progress-step-current'
                        : isReached
                            ? 'progress-step progress-step-complete'
                            : 'progress-step',

                markerClass:
                    isCurrent
                        ? 'progress-marker progress-marker-current'
                        : isReached
                            ? 'progress-marker progress-marker-complete'
                            : 'progress-marker',

                ariaCurrent:
                    isCurrent
                        ? 'step'
                        : null
            };
        });
    }

    get currentProgressMessage() {
        const status =
            this.serviceRequest?.customerStatus;

        switch (status) {
            case 'Waiting on Parts':
                return 'Service is underway and is currently waiting for required parts.';

            case 'Follow-Up Required':
                return 'Additional service is required before this request can be completed.';

            case 'Visit Scheduled':
                return 'Your request has progressed to a service visit.';

            case 'Service in Progress':
                return 'Your machine is currently moving through the service process.';

            case 'Completed':
                return 'This service request has been completed.';

            default:
                return 'Your service request has been received and is being reviewed by MillTrack.';
        }
    }


    // =========================================================
    // What Happens Next
    // Dispatch_Status__c is authoritative for Work Orders.
    // =========================================================

    get nextStep() {
        const dispatchStatus =
            this.serviceVisit?.dispatchStatus;

        if (dispatchStatus) {
            switch (dispatchStatus) {
                case 'Pending':
                    return {
                        title: 'MillTrack is reviewing your request',
                        message:
                            'Your service visit has been created. The MillTrack service team is reviewing the reported issue and determining the appropriate next action.'
                    };

                case 'Parts to Order':
                    return {
                        title: 'Required parts are being identified',
                        message:
                            'MillTrack is coordinating the parts needed for your service visit. Service will continue once the required parts are ready.'
                    };

                case 'Waiting on Parts':
                    return {
                        title: 'Your service visit is waiting on parts',
                        message:
                            'The required parts are being coordinated. Your service visit will continue once those parts are available.'
                    };

                case 'Ready_to_Assign':
                    return {
                        title: 'Your visit is ready for technician assignment',
                        message:
                            'MillTrack has reviewed the request and your service visit is ready to be assigned to an appropriate technician.'
                    };

                case 'Assigned':
                    return {
                        title: 'A technician has been assigned',
                        message:
                            'A MillTrack technician has been assigned to your service visit. Open the Service Visit for the latest scheduling and service information.'
                    };

                case 'In Progress':
                    return {
                        title: 'Your service visit is in progress',
                        message:
                            'Your technician is actively working through the reported machine issue. Service updates will continue to appear in the related Service Visit.'
                    };

                case 'Temporary Fix':
                    return {
                        title: 'A temporary fix has been applied',
                        message:
                            'The machine has received a temporary repair, but additional follow-up service is still required before the issue is considered fully resolved.'
                    };

                case 'Completed':
                    return {
                        title: 'Service has been completed',
                        message:
                            'The related service visit has been completed. You can open the Service Visit to review the final service activity.'
                    };

                case 'Cancelled':
                    return {
                        title: 'This service visit is no longer active',
                        message:
                            'The related service visit has been cancelled. If the machine still requires assistance, contact MillTrack or submit a new service request.'
                    };

                default:
                    return {
                        title: 'MillTrack is managing your service visit',
                        message:
                            'Your service request is active. Open the related Service Visit for the latest scheduling and service information.'
                    };
            }
        }

        const caseStatus =
            this.serviceRequest?.customerStatus;

        switch (caseStatus) {
            case 'Visit Scheduled':
                return {
                    title: 'Your service visit is being prepared',
                    message:
                        'MillTrack is coordinating the next service action for your machine. Service Visit details will appear once they are available.'
                };

            case 'Service in Progress':
                return {
                    title: 'Your request is moving through service',
                    message:
                        'MillTrack is actively working on your request. Additional service details will appear here as the work progresses.'
                };

            case 'Waiting on Parts':
                return {
                    title: 'Parts are required before service can continue',
                    message:
                        'MillTrack is coordinating the parts needed to continue work on your machine.'
                };

            case 'Follow-Up Required':
                return {
                    title: 'Additional service is required',
                    message:
                        'The request requires follow-up before it can be completed. MillTrack will continue coordinating the next service action.'
                };

            case 'Completed':
                return {
                    title: 'Your request has been completed',
                    message:
                        'MillTrack has completed this service request. Any available completed service information can be reviewed from the related records.'
                };

            default:
                return {
                    title: 'MillTrack is reviewing your request',
                    message:
                        'Your issue has been received. The service team will review the information and prepare the appropriate next service action.'
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
            this.serviceRequest
        );
    }

    get hasMachine() {
        return Boolean(
            this.machine
        );
    }

    get hasMachineImage() {
        return Boolean(
            this.machine?.imageUrl
        );
    }

    get hasServiceVisit() {
        return Boolean(
            this.serviceVisit
        );
    }

    get hasSlaDueDate() {
        return Boolean(
            this.serviceRequest?.slaDueDate
        );
    }

    get hasClosedDate() {
        return Boolean(
            this.serviceRequest?.closedDate
        );
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

    handleViewServiceVisit() {
        if (!this.serviceVisit?.id) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.serviceVisit.id,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }


    // =========================================================
    // Status Classes
    // =========================================================

    getCaseStatusClass(status) {
        const normalized =
            (status || '').toLowerCase();

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
        const normalized =
            (status || '').toLowerCase();

        if (
            normalized.includes('needs service') ||
            normalized.includes('out of service')
        ) {
            return 'machine-status machine-status-warning';
        }

        if (
            normalized.includes('temporary fix')
        ) {
            return 'machine-status machine-status-info';
        }

        if (
            normalized.includes('active')
        ) {
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
            .map(segment => encodeURIComponent(segment))
            .join('/');

        return `${baseUrl}/${encodedPath}`;
    }


    // =========================================================
    // Error Handling
    // =========================================================

    normalizeError(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'Your service request could not be loaded. Please refresh the page and try again.';
    }
}