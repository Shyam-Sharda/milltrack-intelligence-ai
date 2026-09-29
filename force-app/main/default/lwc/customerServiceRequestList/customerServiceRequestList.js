import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getServiceRequests from '@salesforce/apex/CustomerServiceRequestListController.getServiceRequests';

export default class CustomerServiceRequestList extends NavigationMixin(LightningElement) {
    serviceRequests = [];
    error;
    isLoading = true;
    activeFilter = 'All';

    @wire(getServiceRequests)
    wiredServiceRequests({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.serviceRequests = this.prepareServiceRequests(data);
            this.error = undefined;
        } else if (error) {
            this.serviceRequests = [];
            this.error = error;
        }
    }

    get hasServiceRequests() {
        return this.filteredServiceRequests.length > 0;
    }

    get hasError() {
        return !!this.error;
    }

    get filteredServiceRequests() {
        if (this.activeFilter === 'Open') {
            return this.serviceRequests.filter(
                record =>
                    record.customerStatus !== 'Completed' &&
                    record.customerStatus !== 'Service Cancelled'
            );
        }

        if (this.activeFilter === 'Completed') {
            return this.serviceRequests.filter(
                record => record.customerStatus === 'Completed'
            );
        }

        return this.serviceRequests;
    }

    get allFilterClass() {
        return this.activeFilter === 'All'
            ? 'filter-button filter-button-active'
            : 'filter-button';
    }

    get openFilterClass() {
        return this.activeFilter === 'Open'
            ? 'filter-button filter-button-active'
            : 'filter-button';
    }

    get completedFilterClass() {
        return this.activeFilter === 'Completed'
            ? 'filter-button filter-button-active'
            : 'filter-button';
    }

    get resultCountLabel() {
        const count = this.filteredServiceRequests.length;
        return `${count} ${count === 1 ? 'Service Request' : 'Service Requests'}`;
    }

    get errorMessage() {
        return this.error?.body?.message ||
            'Please refresh the page and try again.';
    }

    prepareServiceRequests(records) {
        return (records || []).map(record => {
            const customerStatus =
                record.customerStatus || 'Request Received';

            return {
                ...record,
                caseNumberDisplay:
                    record.caseNumber || 'Not available',
                subjectDisplay:
                    record.subject || 'Service Request',
                assetNameDisplay:
                    record.assetName || 'Machine not available',
                customerStatusDisplay:
                    customerStatus,
                priorityDisplay:
                    record.priority || 'Not specified',
                statusClass:
                    this.getStatusClass(customerStatus),
                priorityClass:
                    this.getPriorityClass(record.priority),
                hasScheduledVisit:
                    !!record.scheduledVisit,
                hasClosedDate:
                    !!record.closedDate
            };
        });
    }

    getStatusClass(status) {
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

    handleFilter(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
    }

    handleRecordNavigation(event) {
        const recordId = event.currentTarget.dataset.id;

        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    handleAssetNavigation(event) {
        const recordId = event.currentTarget.dataset.id;

        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Asset',
                actionName: 'view'
            }
        });
    }
}