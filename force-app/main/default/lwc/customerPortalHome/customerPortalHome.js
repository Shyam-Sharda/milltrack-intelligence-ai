import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeData from '@salesforce/apex/CustomerPortalHomeController.getHomeData';

import PORTAL_MEDIA from '@salesforce/resourceUrl/MillTrack_Portal_Media';

export default class CustomerPortalHome extends NavigationMixin(LightningElement) {
    @api heroImageUrl;

    heroImage = `${PORTAL_MEDIA}/images/portal-header.jpg`;
    machineCardImage = `${PORTAL_MEDIA}/images/machine-card.jpg`;
    serviceRequestCardImage = `${PORTAL_MEDIA}/images/service-request-card.jpg`;
    workOrderCardImage = `${PORTAL_MEDIA}/images/work-order-card.jpg`;

    homeData;
    error;
    isLoading = true;

    @wire(getHomeData)
    wiredHomeData({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.homeData = {
                ...data,
                machines: this.prepareMachines(data.machines),
                serviceRequests: this.prepareServiceRequests(data.serviceRequests),
                workOrders: this.prepareWorkOrders(data.workOrders)
            };

            this.error = undefined;
        } else if (error) {
            this.homeData = undefined;
            this.error = error;
        }
    }

    get hasData() {
        return !!this.homeData;
    }

    get hasError() {
        return !!this.error;
    }

    get customerFirstName() {
        return this.homeData?.customerFirstName;
    }

    get welcomeTitle() {
        return this.customerFirstName
            ? `Welcome to MillTrack, ${this.customerFirstName}`
            : 'Welcome to MillTrack';
    }

    get machines() {
        return this.homeData?.machines || [];
    }

    get serviceRequests() {
        return this.homeData?.serviceRequests || [];
    }

    get workOrders() {
        return this.homeData?.workOrders || [];
    }

    get machineCount() {
        return this.homeData?.machineCount || 0;
    }

    get openServiceRequestCount() {
        return this.homeData?.openServiceRequestCount || 0;
    }

    get activeWorkOrderCount() {
        return this.homeData?.activeWorkOrderCount || 0;
    }

    get hasMachines() {
        return this.machines.length > 0;
    }

    get hasServiceRequests() {
        return this.serviceRequests.length > 0;
    }

    get hasWorkOrders() {
        return this.workOrders.length > 0;
    }

    get machineCountLabel() {
        return `${this.machineCount} ${this.machineCount === 1 ? 'Machine' : 'Machines'}`;
    }

    get serviceRequestCountLabel() {
        return `${this.openServiceRequestCount} ${this.openServiceRequestCount === 1 ? 'Open Request' : 'Open Requests'}`;
    }

    get workOrderCountLabel() {
        return `${this.activeWorkOrderCount} ${this.activeWorkOrderCount === 1 ? 'Active Work Order' : 'Active Work Orders'}`;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Please refresh the page and try again.';
    }

    prepareMachines(records) {
        return (records || []).map(machine => {
            return {
                ...machine,
                manufacturerDisplay: machine.manufacturer || 'Manufacturer not available',
                modelDisplay: machine.model || 'Model not available',
                serialDisplay: machine.serialNumber || 'Not available',
                statusDisplay: machine.status || 'Status unavailable',
                statusClass: this.getMachineStatusClass(machine.status)
            };
        });
    }

    prepareServiceRequests(records) {
        return (records || []).map(request => {
            return {
                ...request,
                subjectDisplay: request.subject || 'Service Request',
                assetNameDisplay: request.assetName || 'Machine not available',
                statusDisplay: this.getCustomerCaseStatus(request.status),
                priorityDisplay: request.priority || 'Not specified',
                statusClass: this.getCaseStatusClass(request.status),
                priorityClass: this.getPriorityClass(request.priority)
            };
        });
    }

    prepareWorkOrders(records) {
        return (records || []).map(workOrder => {
            return {
                ...workOrder,
                subjectDisplay: workOrder.subject || 'Service Work Order',
                assetNameDisplay: workOrder.assetName || 'Machine not available',
                statusClass: this.getWorkOrderStatusClass(workOrder.customerStatus)
            };
        });
    }

    getCustomerCaseStatus(status) {
        switch (status) {
            case 'New':
                return 'Request Received';
            case 'Scheduled':
                return 'Visit Scheduled';
            case 'In Progress':
                return 'Service in Progress';
            case 'Waiting on Parts':
                return 'Waiting on Parts';
            case 'Follow-Up Required':
                return 'Follow-Up Required';
            default:
                return status || 'Under Review';
        }
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

    getCaseStatusClass(status) {
        switch (status) {
            case 'New':
                return 'status-pill status-blue';
            case 'Scheduled':
                return 'status-pill status-teal';
            case 'In Progress':
                return 'status-pill status-teal';
            case 'Waiting on Parts':
                return 'status-pill status-tan';
            case 'Follow-Up Required':
                return 'status-pill status-orange';
            default:
                return 'status-pill status-blue';
        }
    }

    getWorkOrderStatusClass(status) {
        switch (status) {
            case 'Waiting on Parts':
                return 'status-pill status-tan';
            case 'Visit Scheduled':
                return 'status-pill status-teal';
            case 'Service in Progress':
                return 'status-pill status-teal';
            case 'Request Received':
                return 'status-pill status-blue';
            case 'Under Review':
                return 'status-pill status-blue';
            default:
                return 'status-pill status-blue';
        }
    }

    getPriorityClass(priority) {
        switch (priority) {
            case 'Critical':
                return 'priority-pill priority-critical';
            case 'High':
                return 'priority-pill priority-high';
            case 'Medium':
                return 'priority-pill priority-medium';
            case 'Low':
                return 'priority-pill priority-low';
            default:
                return 'priority-pill priority-neutral';
        }
    }

    handleOpenAiChat() {
        window.postMessage(
            'MILLTRACK_OPEN_AI_CHAT',
            window.location.origin
        );
    }

    handleSectionNavigation(event) {
        const target = event.currentTarget.dataset.target;
        const section = this.template.querySelector(`[data-section="${target}"]`);

        if (section) {
            section.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    }

    handleRecordNavigation(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName = event.currentTarget.dataset.object;

        if (!recordId || !objectApiName) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }
}