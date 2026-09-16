import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

const FIELDS = [
    'WorkOrder.WorkOrderNumber',
    'WorkOrder.Subject',
    'WorkOrder.Dispatch_Status__c',
    'WorkOrder.Priority',
    'WorkOrder.AssetId',
    'WorkOrder.AccountId',
    'WorkOrder.Scheduled_Visit__c',
    'WorkOrder.Suggested_Technician__c'
];

const OPTIONAL_FIELDS = [
    'WorkOrder.Asset.Name',
    'WorkOrder.Account.Name',
    'WorkOrder.Suggested_Technician__r.Name'
];

const ACTION_START_WORK = 'WorkOrder.Start_Work_LWC';
const ACTION_REQUEST_PARTS = 'WorkOrder.Request_Parts_LWC';
const ACTION_TEMPORARY_FIX = 'WorkOrder.Temporary_Fix_Follow_Up';
const ACTION_COMPLETE = 'WorkOrder.Complete_Work_Order_LWC';

export default class TechnicianWorkOrderHeader extends NavigationMixin(LightningElement) {
    @api recordId;

    workOrder;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS, optionalFields: OPTIONAL_FIELDS })
    wiredWorkOrder({ data, error }) {
        if (data) {
            this.workOrder = data;
            this.error = undefined;
        } else if (error) {
            this.workOrder = undefined;
            this.error = error;
        }
    }

    get isLoading() { return !this.workOrder && !this.error; }
    get hasRecord() { return Boolean(this.workOrder); }

    value(field) { return this.workOrder ? getFieldValue(this.workOrder, field) : null; }
    display(value, fallback = '—') { return value === null || value === undefined || value === '' ? fallback : value; }

    get workOrderNumber() { return this.display(this.value('WorkOrder.WorkOrderNumber')); }
    get subject() { return this.display(this.value('WorkOrder.Subject'), 'No subject provided'); }
    get assetName() { return this.display(this.value('WorkOrder.Asset.Name'), 'No machine'); }
    get accountName() { return this.display(this.value('WorkOrder.Account.Name'), 'No customer'); }
    get technicianName() { return this.display(this.value('WorkOrder.Suggested_Technician__r.Name'), 'Not assigned'); }

    get dispatchStatus() { return this.value('WorkOrder.Dispatch_Status__c'); }
    get dispatchStatusLabel() { return this.dispatchStatus === 'Ready_to_Assign' ? 'Ready to Assign' : this.display(this.dispatchStatus, 'No Status'); }

    get dispatchStatusClass() {
        if (this.dispatchStatus === 'Assigned') return 'pill status-assigned';
        if (this.dispatchStatus === 'In Progress') return 'pill status-progress';
        if (this.dispatchStatus === 'Waiting on Parts') return 'pill status-parts';
        if (this.dispatchStatus === 'Temporary Fix') return 'pill status-warning';
        if (this.dispatchStatus === 'Completed') return 'pill status-complete';
        return 'pill status-neutral';
    }

    get priority() { return this.value('WorkOrder.Priority'); }
    get priorityLabel() { return `${this.display(this.priority, 'No')} Priority`; }

    get priorityClass() {
        if (this.priority === 'Critical') return 'pill priority-critical';
        if (this.priority === 'High') return 'pill priority-high';
        if (this.priority === 'Medium') return 'pill priority-medium';
        if (this.priority === 'Low') return 'pill priority-low';
        return 'pill status-neutral';
    }

    get scheduledVisit() {
        const value = this.value('WorkOrder.Scheduled_Visit__c');

        if (!value) return 'Not scheduled';

        try {
            return new Intl.DateTimeFormat('en-CA', {
                year: 'numeric',
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit'
            }).format(new Date(value));
        } catch (e) {
            return value;
        }
    }

    get showStartWork() { return this.dispatchStatus === 'Assigned'; }
    get showActiveRepairActions() { return this.dispatchStatus === 'In Progress'; }
    get hasActions() { return this.showStartWork || this.showActiveRepairActions; }

    launchAction(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName },
            state: { recordId: this.recordId }
        });
    }

    handleStartWork() { this.launchAction(ACTION_START_WORK); }
    handleRequestParts() { this.launchAction(ACTION_REQUEST_PARTS); }
    handleTemporaryFix() { this.launchAction(ACTION_TEMPORARY_FIX); }
    handleComplete() { this.launchAction(ACTION_COMPLETE); }
}