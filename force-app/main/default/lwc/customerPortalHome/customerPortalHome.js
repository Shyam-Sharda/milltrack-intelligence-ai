import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeData from '@salesforce/apex/CustomerPortalHomeController.getHomeData';

import PORTAL_MEDIA from '@salesforce/resourceUrl/MillTrack_Portal_Media';

export default class CustomerPortalHome extends NavigationMixin(LightningElement) {
    @api heroImageUrl;

    heroImage = `${PORTAL_MEDIA}/images/portal-header.jpg`;
    machineCardImage = `${PORTAL_MEDIA}/images/machine-card.jpg`;
    serviceRequestCardImage = `${PORTAL_MEDIA}/images/service-request-card.jpg`;

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
                serviceRequests: this.prepareServiceRequests(data.serviceRequests)
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

    get machineCount() {
        return this.homeData?.machineCount || 0;
    }

    get recentServiceRequestCount() {
        return this.homeData?.recentServiceRequestCount || 0;
    }

    get hasMachines() {
        return this.machines.length > 0;
    }

    get hasServiceRequests() {
        return this.serviceRequests.length > 0;
    }

    get machineCountLabel() {
        return `${this.machineCount} ${this.machineCount === 1 ? 'Machine' : 'Machines'}`;
    }

    get serviceRequestCountLabel() {
        return `${this.recentServiceRequestCount} ${
            this.recentServiceRequestCount === 1
                ? 'Recent Request'
                : 'Recent Requests'
        }`;
    }

    get errorMessage() {
        return this.error?.body?.message ||
            'Please refresh the page and try again.';
    }

    prepareMachines(records) {
        return (records || []).map(machine => {
            return {
                ...machine,
                manufacturerDisplay:
                    machine.manufacturer || 'Manufacturer not available',
                modelDisplay:
                    machine.model || 'Model not available',
                serialDisplay:
                    machine.serialNumber || 'Not available',
                statusDisplay:
                    machine.status || 'Status unavailable',
                statusClass:
                    this.getMachineStatusClass(machine.status)
            };
        });
    }

    prepareServiceRequests(records) {
        return (records || []).map(request => {
            const customerStatus =
                request.customerStatus || 'Request Received';

            return {
                ...request,
                caseNumberDisplay:
                    request.caseNumber || 'Not available',
                subjectDisplay:
                    request.subject || 'Service Request',
                assetNameDisplay:
                    request.assetName || 'Machine not available',
                statusDisplay:
                    customerStatus,
                priorityDisplay:
                    request.priority || 'Not specified',
                statusClass:
                    this.getServiceRequestStatusClass(customerStatus),
                priorityClass:
                    this.getPriorityClass(request.priority)
            };
        });
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

    getServiceRequestStatusClass(status) {
        switch (status) {
            case 'Request Received':
                return 'status-pill status-blue';
            case 'Under Review':
                return 'status-pill status-blue';
            case 'Visit Scheduled':
                return 'status-pill status-teal';
            case 'Service in Progress':
                return 'status-pill status-teal';
            case 'Waiting on Parts':
                return 'status-pill status-tan';
            case 'Follow-Up Required':
                return 'status-pill status-orange';
            case 'Completed':
                return 'status-pill status-green';
            case 'Service Cancelled':
                return 'status-pill status-gray';
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
        const section =
            this.template.querySelector(
                `[data-section="${target}"]`
            );

        if (section) {
            section.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    }

    handleRecordNavigation(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectApiName =
            event.currentTarget.dataset.object;

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

    handleViewAllServiceRequests() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }
}