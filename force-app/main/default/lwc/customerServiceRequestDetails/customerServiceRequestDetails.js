import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getServiceRequestDetails from '@salesforce/apex/CustomerServiceRequestDetailsController.getServiceRequestDetails';
import MACHINE_MEDIA from '@salesforce/resourceUrl/MillTrack_Machine_Media';

export default class CustomerServiceRequestDetails extends LightningElement {
    _recordId;

    isLoading = true;
    errorMessage;

    serviceRequest;
    machine;
    serviceVisit;
    progress;
    resolution;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (!value || value === this._recordId) {
            return;
        }

        this._recordId = value;
        this.loadServiceRequestDetails();
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
            this.loadServiceRequestDetails();
        }
    }

    async loadServiceRequestDetails() {
        if (!this._recordId) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const data = await getServiceRequestDetails({
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

            this.progress = data?.progress
                ? this.prepareProgress(data.progress)
                : undefined;

            this.resolution = data?.resolution
                ? this.prepareResolution(data.resolution)
                : undefined;
        } catch (error) {
            this.clearData();
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isLoading = false;
        }
    }

    prepareServiceRequest(serviceRequest) {
        return {
            ...serviceRequest,
            requestNumberDisplay: serviceRequest.caseNumber || 'Not available',
            subjectDisplay: serviceRequest.subject || 'Service Request',
            descriptionDisplay: serviceRequest.description || 'No description was provided.',
            errorCodeDisplay: serviceRequest.errorCode || 'None reported',
            priorityDisplay: serviceRequest.priority || 'Not specified',
            customerStatusDisplay: serviceRequest.customerStatus || 'Request Received',
            statusClass: this.getStatusClass(serviceRequest.customerStatus),
            priorityClass: this.getPriorityClass(serviceRequest.priority)
        };
    }

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
            statusDisplay: machine.status || 'Not recorded',
            statusClass: this.getMachineStatusClass(machine.status)
        };
    }

    prepareServiceVisit(serviceVisit) {
        return {
            ...serviceVisit,
            hasScheduledVisit: Boolean(serviceVisit.scheduledVisit),
            hasWorkEnded: Boolean(serviceVisit.workEndedDateTime),
            scheduledVisitDisplay: serviceVisit.scheduledVisit || null,
            workEndedDisplay: serviceVisit.workEndedDateTime || null
        };
    }

    prepareProgress(progress) {
        return {
            ...progress,
            stages: (progress.stages || []).map((stage, index) => ({
                ...stage,
                number: index + 1,
                cssClass: `progress-step progress-step-${stage.state}`,
                markerClass: `progress-marker progress-marker-${stage.state}`,
                lineClass: `progress-line progress-line-${stage.state}`,
                isCompleted: stage.state === 'completed',
                isCurrent: stage.state === 'current',
                isUpcoming: stage.state === 'upcoming'
            }))
        };
    }

    prepareResolution(resolution) {
        return {
            ...resolution,
            rootCauseDisplay: resolution.rootCause || 'No root cause was recorded.',
            summaryDisplay: resolution.summary || 'No repair summary was recorded.',
            partsUsedDisplay: resolution.partsUsed || 'No parts recorded',
            laborHoursDisplay: resolution.laborHours != null
                ? `${resolution.laborHours} hours`
                : 'Not recorded'
        };
    }

    clearData() {
        this.serviceRequest = undefined;
        this.machine = undefined;
        this.serviceVisit = undefined;
        this.progress = undefined;
        this.resolution = undefined;
    }

    get hasData() {
        return Boolean(this.serviceRequest);
    }

    get hasMachine() {
        return Boolean(this.machine);
    }

    get hasMachineImage() {
        return Boolean(this.machine?.imageUrl);
    }

    get hasServiceVisit() {
        return Boolean(this.serviceVisit);
    }

    get hasProgress() {
        return Boolean(this.progress?.stages?.length);
    }

    get hasResolution() {
        return Boolean(this.resolution);
    }

    get resolutionCardClass() {
        if (!this.hasResolution) {
            return 'resolution-card resolution-card-pending';
        }

        if (this.resolution?.outcome === 'Follow-up Required') {
            return 'resolution-card resolution-card-followup';
        }

        return 'resolution-card resolution-card-complete';
    }

    get resolutionIconClass() {
        return this.hasResolution
            ? 'resolution-check resolution-check-complete'
            : 'resolution-check resolution-check-pending';
    }

    get resolutionIconName() {
        return this.hasResolution
            ? 'utility:check'
            : 'utility:clock';
    }

    get resolutionEyebrow() {
        return this.hasResolution
            ? 'COMPLETED SERVICE'
            : 'SERVICE RESOLUTION';
    }

    get resolutionTitle() {
        return this.hasResolution
            ? 'Service Resolution'
            : 'Service not yet completed';
    }

    get resolutionStatus() {
        if (!this.hasResolution) {
            return 'Pending';
        }

        return this.resolution?.outcome || 'Resolved';
    }

    get resolutionStatusClass() {
        if (!this.hasResolution) {
            return 'resolution-outcome resolution-pending';
        }

        if (this.resolution?.outcome === 'Follow-up Required') {
            return 'resolution-outcome resolution-followup';
        }

        return 'resolution-outcome resolution-resolved';
    }

    getStatusClass(status) {
        switch (status) {
            case 'Completed':
                return 'status-pill status-completed';
            case 'Service in Progress':
                return 'status-pill status-progress';
            case 'Visit Scheduled':
                return 'status-pill status-scheduled';
            case 'Waiting on Parts':
                return 'status-pill status-parts';
            case 'Service Cancelled':
                return 'status-pill status-cancelled';
            case 'Follow-Up Required':
                return 'status-pill status-followup';
            case 'Under Review':
                return 'status-pill status-review';
            default:
                return 'status-pill status-received';
        }
    }

    getPriorityClass(priority) {
        switch (priority) {
            case 'High':
                return 'priority-display priority-high';
            case 'Medium':
                return 'priority-display priority-medium';
            case 'Low':
                return 'priority-display priority-low';
            default:
                return 'priority-display';
        }
    }

    getMachineStatusClass(status) {
        switch (status) {
            case 'Active':
                return 'machine-status machine-active';
            case 'Needs Service':
                return 'machine-status machine-service';
            case 'Out of Service':
                return 'machine-status machine-out';
            default:
                return 'machine-status';
        }
    }

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