import { LightningElement, api, wire } from 'lwc';
import { getRecord, getRecords, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { getRelatedListsInfo, getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const CORE_FIELDS = [
    'WorkOrder.WorkOrderNumber',
    'WorkOrder.Subject',
    'WorkOrder.Dispatch_Status__c',
    'WorkOrder.Priority',
    'WorkOrder.AccountId',
    'WorkOrder.ContactId',
    'WorkOrder.AssetId',
    'WorkOrder.CaseId',
    'WorkOrder.OwnerId',
    'WorkOrder.Suggested_Technician__c',
    'WorkOrder.Service_Manager__c',
    'WorkOrder.Problem_Summary__c',
    'WorkOrder.Recommended_Solution__c',
    'WorkOrder.Recommended_Fix_Summary__c',
    'WorkOrder.Recommended_Tools__c',
    'WorkOrder.Recommended_Parts__c',
    'WorkOrder.Previous_Failure__c',
    'WorkOrder.Scheduled_Visit__c',
    'WorkOrder.Labor_Hours__c',
    'WorkOrder.Technician_Notes__c',
    'WorkOrder.Work_Started_Date_Time__c',
    'WorkOrder.Work_Ended_Date_Time__c',
    'WorkOrder.CreatedDate',
    'WorkOrder.LastModifiedDate'
];

const OPTIONAL_FIELDS = [
    'WorkOrder.Account.Name',
    'WorkOrder.Contact.Name',
    'WorkOrder.Contact.Phone',
    'WorkOrder.Asset.Name',
    'WorkOrder.Asset.Manufacturer__c',
    'WorkOrder.Asset.Model__c',
    'WorkOrder.Asset.Serial_Number__c',
    'WorkOrder.Asset.Machine_Status__c',
    'WorkOrder.Asset.Warranty_Start_Date__c',
    'WorkOrder.Asset.Warranty_End_Date__c',
    'WorkOrder.Case.CaseNumber',
    'WorkOrder.Case.Status',
    'WorkOrder.Owner.Name',
    'WorkOrder.Suggested_Technician__r.Name',
    'WorkOrder.Service_Manager__r.Name'
];

const WOP_FIELDS = [
    'Work_Order_Part__c.Name',
    'Work_Order_Part__c.Part_Catalog__c',
    'Work_Order_Part__c.Order_Status__c',
    'Work_Order_Part__c.Quantity__c'
];

const PART_CATALOG_FIELDS = [
    'Part_Catalog__c.Name',
    'Part_Catalog__c.Part_Number__c'
];

const LOG_FIELDS = [
    'Maintenance_Log__c.Name',
    'Maintenance_Log__c.Maintenance_Date__c',
    'Maintenance_Log__c.Maintenance_Type__c',
    'Maintenance_Log__c.Issue_Resolved__c',
    'Maintenance_Log__c.Follow_Up_Required__c'
];

export default class ManagerWorkOrderSummary extends NavigationMixin(LightningElement) {
    @api recordId;

    workOrder;
    workOrderParts = [];
    partCatalogRequests;
    partCatalogRequestKey = '';
    maintenanceLogs = [];

    workOrderPartCount = 0;
    maintenanceLogCount = 0;

    workOrderPartsRelatedListId;
    maintenanceLogsRelatedListId;

    errorMessage;
    showEditModal = false;
    isSaving = false;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: CORE_FIELDS,
        optionalFields: OPTIONAL_FIELDS
    })
    wiredWorkOrder({ data, error }) {
        if (data) {
            this.workOrder = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.workOrder = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    @wire(getRelatedListsInfo, { parentObjectApiName: 'WorkOrder' })
    wiredRelatedLists({ data }) {
        if (!data) return;

        const lists = data.relatedLists || [];

        this.workOrderPartsRelatedListId = this.findRelatedListId(lists, 'work order parts');
        this.maintenanceLogsRelatedListId = this.findRelatedListId(lists, 'maintenance logs');
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$workOrderPartsRelatedListId',
        fields: WOP_FIELDS,
        pageSize: 4
    })
    wiredWorkOrderParts({ data }) {
        if (!data) {
            this.workOrderParts = [];
            this.workOrderPartCount = 0;
            this.partCatalogRequests = undefined;
            this.partCatalogRequestKey = '';
            return;
        }

        this.workOrderPartCount = data.count ?? data.records?.length ?? 0;

        this.workOrderParts = (data.records || []).map(record => {
            const status = this.relatedValue(record, 'Order_Status__c', 'Unknown');
            const partCatalogId = this.relatedRawValue(record, 'Part_Catalog__c');

            return {
                id: record.id,
                name: this.relatedValue(record, 'Name', 'Work Order Part'),
                partCatalogId,
                partName: partCatalogId ? 'Loading part...' : 'No catalog part',
                partNumber: '',
                status,
                quantity: this.relatedValue(record, 'Quantity__c', '—'),
                statusClass: this.relatedStatusClass(status),
                url: this.recordUrl('Work_Order_Part__c', record.id)
            };
        });

        const partCatalogIds = [
            ...new Set(
                this.workOrderParts
                    .map(part => part.partCatalogId)
                    .filter(Boolean)
            )
        ];

        const requestKey = partCatalogIds.slice().sort().join(',');

        if (requestKey !== this.partCatalogRequestKey) {
            this.partCatalogRequestKey = requestKey;

            this.partCatalogRequests = partCatalogIds.length
                ? [{
                    recordIds: partCatalogIds,
                    fields: PART_CATALOG_FIELDS
                }]
                : undefined;
        }
    }

    @wire(getRecords, { records: '$partCatalogRequests' })
    wiredPartCatalogs({ data }) {
        if (!data?.results?.length) return;

        const catalogById = new Map();

        data.results.forEach(item => {
            if (item.statusCode !== 200 || !item.result) return;

            const record = item.result;

            catalogById.set(record.id, {
                name: this.catalogValue(record, 'Name', 'Catalog Part'),
                partNumber: this.catalogValue(record, 'Part_Number__c', 'No part number')
            });
        });

        this.workOrderParts = this.workOrderParts.map(part => {
            if (!part.partCatalogId) return part;

            const catalog = catalogById.get(part.partCatalogId);

            if (!catalog) {
                return {
                    ...part,
                    partName: 'Catalog Part',
                    partNumber: 'No part number'
                };
            }

            return {
                ...part,
                partName: catalog.name,
                partNumber: catalog.partNumber
            };
        });
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$maintenanceLogsRelatedListId',
        fields: LOG_FIELDS,
        pageSize: 4
    })
    wiredMaintenanceLogs({ data }) {
        if (!data) {
            this.maintenanceLogs = [];
            this.maintenanceLogCount = 0;
            return;
        }

        this.maintenanceLogCount = data.count ?? data.records?.length ?? 0;

        this.maintenanceLogs = (data.records || []).map(record => {
            const resolved = this.relatedRawValue(record, 'Issue_Resolved__c');
            const followUp = this.relatedRawValue(record, 'Follow_Up_Required__c');

            return {
                id: record.id,
                name: this.relatedValue(record, 'Name', 'Maintenance Log'),
                date: this.formatDate(
                    this.relatedRawValue(record, 'Maintenance_Date__c'),
                    'No date'
                ),
                type: this.relatedValue(record, 'Maintenance_Type__c', 'Service'),
                outcome: resolved
                    ? 'Issue Resolved'
                    : followUp
                        ? 'Follow-Up Required'
                        : 'Service Visit',
                url: this.recordUrl('Maintenance_Log__c', record.id)
            };
        });
    }

    get hasRecord() { return !!this.workOrder; }
    get isLoading() { return !this.workOrder && !this.errorMessage; }
    get hasWorkOrderParts() { return this.workOrderParts.length > 0; }
    get hasMaintenanceLogs() { return this.maintenanceLogs.length > 0; }

    get workOrderPartCountLabel() {
        return `${this.workOrderPartCount} ${this.workOrderPartCount === 1 ? 'record' : 'records'}`;
    }

    get maintenanceLogCountLabel() {
        return `${this.maintenanceLogCount} ${this.maintenanceLogCount === 1 ? 'record' : 'records'}`;
    }

    value(field) {
        return this.workOrder ? getFieldValue(this.workOrder, field) : null;
    }

    display(value, fallback = '—') {
        return value === null || value === undefined || value === ''
            ? fallback
            : value;
    }

    recordUrl(objectName, id) {
        return id ? `/lightning/r/${objectName}/${id}/view` : null;
    }

    relatedRawValue(record, fieldName) {
        const field = record?.fields?.[fieldName];
        return field ? field.value : null;
    }

    relatedValue(record, fieldName, fallback = '—') {
        const field = record?.fields?.[fieldName];
        if (!field) return fallback;

        return this.display(field.displayValue ?? field.value, fallback);
    }

    catalogValue(record, fieldName, fallback = '—') {
        const field = record?.fields?.[fieldName];
        if (!field) return fallback;

        return this.display(field.displayValue ?? field.value, fallback);
    }

    findRelatedListId(lists, labelText) {
        const match = lists.find(item =>
            (item.label || '').toLowerCase().includes(labelText)
        );

        return match?.relatedListId;
    }

    get workOrderNumber() {
        return this.display(this.value('WorkOrder.WorkOrderNumber'));
    }

    get subject() {
        return this.display(
            this.value('WorkOrder.Subject'),
            'No subject provided'
        );
    }

    get dispatchStatus() {
        return this.value('WorkOrder.Dispatch_Status__c');
    }

    get dispatchStatusLabel() {
        return this.dispatchStatus === 'Ready_to_Assign'
            ? 'Ready to Assign'
            : this.display(this.dispatchStatus, 'No Status');
    }

    get dispatchStatusClass() {
        if (
            this.dispatchStatus === 'Pending'
            || this.dispatchStatus === 'Temporary Fix'
        ) {
            return 'hero-pill status-warning';
        }

        if (
            this.dispatchStatus === 'Parts to Order'
            || this.dispatchStatus === 'Waiting on Parts'
        ) {
            return 'hero-pill status-blue';
        }

        if (
            this.dispatchStatus === 'Ready_to_Assign'
            || this.dispatchStatus === 'Assigned'
        ) {
            return 'hero-pill status-teal';
        }

        if (this.dispatchStatus === 'In Progress') return 'hero-pill status-progress';
        if (this.dispatchStatus === 'Completed') return 'hero-pill status-success';
        if (this.dispatchStatus === 'Cancelled') return 'hero-pill status-cancelled';

        return 'hero-pill status-neutral';
    }

    get priority() {
        return this.value('WorkOrder.Priority');
    }

    get priorityLabel() {
        return `${this.display(this.priority, 'No')} Priority`;
    }

    get priorityClass() {
        if (this.priority === 'Critical') return 'hero-pill priority-critical';
        if (this.priority === 'High') return 'hero-pill priority-high';
        if (this.priority === 'Medium') return 'hero-pill priority-medium';
        if (this.priority === 'Low') return 'hero-pill priority-low';

        return 'hero-pill status-neutral';
    }

    get accountId() {
        return this.value('WorkOrder.AccountId');
    }

    get accountName() {
        return this.display(
            this.value('WorkOrder.Account.Name'),
            'No account'
        );
    }

    get accountUrl() {
        return this.recordUrl('Account', this.accountId);
    }

    get contactId() {
        return this.value('WorkOrder.ContactId');
    }

    get contactName() {
        return this.display(
            this.value('WorkOrder.Contact.Name'),
            'No contact'
        );
    }

    get contactPhone() {
        return this.display(
            this.value('WorkOrder.Contact.Phone'),
            'No phone number'
        );
    }

    get contactUrl() {
        return this.recordUrl('Contact', this.contactId);
    }

    get caseId() {
        return this.value('WorkOrder.CaseId');
    }

    get caseNumber() {
        return this.display(
            this.value('WorkOrder.Case.CaseNumber'),
            'No case'
        );
    }

    get caseStatus() {
        return this.display(
            this.value('WorkOrder.Case.Status'),
            'No status'
        );
    }

    get caseUrl() {
        return this.recordUrl('Case', this.caseId);
    }

    get caseStatusClass() {
        const status = this.value('WorkOrder.Case.Status');

        if (status === 'Closed') return 'status-chip status-success';
        if (status === 'Waiting on Parts') return 'status-chip status-blue';
        if (status === 'Scheduled') return 'status-chip status-teal';
        if (status === 'In Progress') return 'status-chip status-progress';
        if (status === 'Follow-Up Required') return 'status-chip status-warning';
        if (status === 'New') return 'status-chip status-neutral';

        return 'status-chip status-neutral';
    }

    get assetId() {
        return this.value('WorkOrder.AssetId');
    }

    get machineName() {
        return this.display(
            this.value('WorkOrder.Asset.Name'),
            'No machine'
        );
    }

    get manufacturer() {
        return this.value('WorkOrder.Asset.Manufacturer__c');
    }

    get model() {
        return this.value('WorkOrder.Asset.Model__c');
    }

    get machineLabel() {
        return this.manufacturer && this.model
            ? `${this.manufacturer} ${this.model}`
            : this.display(this.manufacturer || this.model);
    }

    get serialNumber() {
        return this.display(
            this.value('WorkOrder.Asset.Serial_Number__c')
        );
    }

    get machineStatus() {
        return this.display(
            this.value('WorkOrder.Asset.Machine_Status__c'),
            'Unknown'
        );
    }

    get warrantyStartDate() {
        return this.formatDate(
            this.value('WorkOrder.Asset.Warranty_Start_Date__c')
        );
    }

    get warrantyEndDate() {
        return this.formatDate(
            this.value('WorkOrder.Asset.Warranty_End_Date__c')
        );
    }

    get assetUrl() {
        return this.recordUrl('Asset', this.assetId);
    }

    get machineStatusClass() {
        const value = this.value('WorkOrder.Asset.Machine_Status__c');

        if (value === 'Active') return 'status-chip machine-active';
        if (value === 'Needs Service') return 'status-chip machine-service';
        if (value === 'Temporary Fix Applied') return 'status-chip machine-temporary';
        if (value === 'Out of Service') return 'status-chip machine-out';

        return 'status-chip machine-neutral';
    }

    get assignedTechnicianId() {
        return this.value('WorkOrder.Suggested_Technician__c');
    }

    get assignedTechnicianName() {
        return this.display(
            this.value('WorkOrder.Suggested_Technician__r.Name'),
            'Not assigned'
        );
    }

    get assignedTechnicianUrl() {
        return this.recordUrl('User', this.assignedTechnicianId);
    }

    get serviceManagerId() {
        return this.value('WorkOrder.Service_Manager__c');
    }

    get serviceManagerName() {
        return this.display(
            this.value('WorkOrder.Service_Manager__r.Name'),
            'Not assigned'
        );
    }

    get serviceManagerUrl() {
        return this.recordUrl('User', this.serviceManagerId);
    }

    get ownerName() {
        return this.display(
            this.value('WorkOrder.Owner.Name'),
            'No owner'
        );
    }

    get problemSummary() {
        return this.display(
            this.value('WorkOrder.Problem_Summary__c'),
            'No problem summary has been recorded.'
        );
    }

    get recommendedSolution() {
        return this.display(
            this.value('WorkOrder.Recommended_Solution__c'),
            'No recommended solution has been recorded.'
        );
    }

    get recommendedFixSummary() {
        return this.display(
            this.value('WorkOrder.Recommended_Fix_Summary__c'),
            'No recommended fix summary has been recorded.'
        );
    }

    get recommendedTools() {
        return this.display(
            this.value('WorkOrder.Recommended_Tools__c'),
            'No tools currently listed.'
        );
    }

    get recommendedParts() {
        return this.display(
            this.value('WorkOrder.Recommended_Parts__c'),
            'No parts currently listed.'
        );
    }

    get technicianNotes() {
        return this.display(
            this.value('WorkOrder.Technician_Notes__c'),
            'No technician service notes have been recorded yet.'
        );
    }

    get previousFailure() {
        return !!this.value('WorkOrder.Previous_Failure__c');
    }

    get previousFailureLabel() {
        return this.previousFailure ? 'Yes' : 'No';
    }

    get previousFailureClass() {
        return this.previousFailure
            ? 'status-chip previous-yes'
            : 'status-chip previous-no';
    }

    get scheduledVisit() {
        return this.formatDateTime(
            this.value('WorkOrder.Scheduled_Visit__c'),
            'Not scheduled'
        );
    }

    get workStarted() {
        return this.formatDateTime(
            this.value('WorkOrder.Work_Started_Date_Time__c'),
            'Not started'
        );
    }

    get workEnded() {
        return this.formatDateTime(
            this.value('WorkOrder.Work_Ended_Date_Time__c'),
            'Not completed'
        );
    }

    get createdDate() {
        return this.formatDateTime(
            this.value('WorkOrder.CreatedDate')
        );
    }

    get lastModifiedDate() {
        return this.formatDateTime(
            this.value('WorkOrder.LastModifiedDate')
        );
    }

    get laborHours() {
        const hours = this.value('WorkOrder.Labor_Hours__c');

        if (hours === null || hours === undefined) return '0.00 hours';

        return `${Number(hours).toFixed(2)} ${Number(hours) === 1 ? 'hour' : 'hours'}`;
    }

    formatDateTime(value, fallback = '—') {
        if (!value) return fallback;

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

    formatDate(value, fallback = '—') {
        if (!value) return fallback;

        try {
            return new Intl.DateTimeFormat('en-CA', {
                year: 'numeric',
                month: 'short',
                day: 'numeric'
            }).format(new Date(`${value}T00:00:00`));
        } catch (e) {
            return value;
        }
    }

    relatedStatusClass(status) {
        if (
            status === 'Received'
            || status === 'Installed'
        ) {
            return 'related-status related-success';
        }

        if (status === 'Requested') return 'related-status related-warning';

        if (
            status === 'Ordered'
            || status === 'Shipped'
        ) {
            return 'related-status related-blue';
        }

        if (status === 'Cancelled') return 'related-status related-cancelled';

        return 'related-status neutral-related-status';
    }

    navigateToRelationship(relationshipApiName) {
        if (!relationshipApiName) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Related List Unavailable',
                    message: 'Salesforce could not resolve this related list for the Work Order.',
                    variant: 'warning'
                })
            );

            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'WorkOrder',
                relationshipApiName,
                actionName: 'view'
            }
        });
    }

    viewAllParts() {
        this.navigateToRelationship(
            this.workOrderPartsRelatedListId
        );
    }

    viewAllLogs() {
        this.navigateToRelationship(
            this.maintenanceLogsRelatedListId
        );
    }

    viewFiles() {
        this.navigateToRelationship(
            'AttachedContentDocuments'
        );
    }

    handleUploadFinished(event) {
        const count = event.detail.files?.length || 0;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Files Uploaded',
                message: `${count} ${count === 1 ? 'file was' : 'files were'} uploaded successfully.`,
                variant: 'success'
            })
        );
    }

    openEditModal() {
        this.showEditModal = true;
    }

    closeEditModal() {
        if (!this.isSaving) this.showEditModal = false;
    }

    handleSubmit() {
        this.isSaving = true;
    }

    async handleSuccess() {
        this.isSaving = false;
        this.showEditModal = false;

        try {
            await notifyRecordUpdateAvailable([
                { recordId: this.recordId }
            ]);
        } catch (e) {
            /* LDS already updated its record cache. */
        }

        this.dispatchEvent(new RefreshEvent());

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Work Order Updated',
                message: 'The Work Order details were saved successfully.',
                variant: 'success'
            })
        );
    }

    handleSaveError(event) {
        this.isSaving = false;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Unable to Save Work Order',
                message: this.reduceError(event.detail),
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    reduceError(error) {
        if (!error) return 'An unexpected error occurred.';

        if (Array.isArray(error.body)) {
            return error.body
                .map(item => item.message)
                .join(', ');
        }

        if (error.body?.message) return error.body.message;

        if (error.detail) {
            if (typeof error.detail === 'string') return error.detail;
            if (error.detail.message) return error.detail.message;
        }

        if (error.message) return error.message;

        return 'An unexpected error occurred.';
    }
}