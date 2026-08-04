import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getOperationsData from '@salesforce/apex/ManagerOperationsCenterController.getOperationsData';

const QUEUE_CONFIG = [
    {
        key: 'newCases',
        countKey: 'newCasesCount',
        label: 'New Cases',
        description: 'New customer service requests'
    },
    {
        key: 'requiresReview',
        countKey: 'requiresReviewCount',
        label: 'Requires Review',
        description: 'AI proposals awaiting manager review'
    },
    {
        key: 'partsToOrder',
        countKey: 'partsToOrderCount',
        label: 'Parts to Order',
        description: 'Parts requiring manager action'
    },
    {
        key: 'waitingOnParts',
        countKey: 'waitingOnPartsCount',
        label: 'Waiting on Parts',
        description: 'Ordered or shipped parts awaiting receipt'
    },
    {
        key: 'readyToAssign',
        countKey: 'readyToAssignCount',
        label: 'Ready to Assign',
        description: 'Work ready for technician dispatch'
    },
    {
        key: 'assignedVisits',
        countKey: 'assignedVisitsCount',
        label: 'Assigned Visits',
        description: 'Scheduled technician visits'
    },
    {
        key: 'activeRepairs',
        countKey: 'activeRepairsCount',
        label: 'Active Repairs',
        description: 'Work currently in progress'
    }
];

const RECORD_BUTTON_COLUMN = {
    label: 'Record',
    type: 'button',
    initialWidth: 145,
    typeAttributes: {
        label: { fieldName: 'recordNumber' },
        name: 'open_record',
        variant: 'base',
        disabled: { fieldName: 'recordNavigationDisabled' }
    }
};

const PRIMARY_ACTION_COLUMN = {
    label: 'Action',
    type: 'button',
    fixedWidth: 205,
    typeAttributes: {
        label: { fieldName: 'actionLabel' },
        name: 'primary_action',
        variant: 'brand-outline',
        disabled: { fieldName: 'actionDisabled' }
    }
};

const SUBJECT_COLUMN = {
    label: 'Subject',
    fieldName: 'displaySubject',
    type: 'text',
    wrapText: true
};

const ACCOUNT_COLUMN = {
    label: 'Account',
    fieldName: 'accountName',
    type: 'text'
};

const MACHINE_COLUMN = {
    label: 'Machine',
    fieldName: 'assetName',
    type: 'text'
};

const PRIORITY_COLUMN = {
    label: 'Priority',
    fieldName: 'priority',
    type: 'text',
    initialWidth: 100
};

const STATUS_COLUMN = {
    label: 'Status',
    fieldName: 'status',
    type: 'text',
    initialWidth: 135
};

const TECHNICIAN_COLUMN = {
    label: 'Technician',
    fieldName: 'technicianName',
    type: 'text'
};

const SCHEDULED_VISIT_COLUMN = {
    label: 'Scheduled Visit',
    fieldName: 'scheduledVisit',
    type: 'date',
    initialWidth: 175,
    typeAttributes: {
        year: 'numeric',
        month: 'short',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    }
};

const CASE_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    SUBJECT_COLUMN,
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    PRIORITY_COLUMN,
    PRIMARY_ACTION_COLUMN
];

const REQUIRES_REVIEW_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    SUBJECT_COLUMN,
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    PRIORITY_COLUMN,
    STATUS_COLUMN,
    PRIMARY_ACTION_COLUMN
];

const PARTS_TO_ORDER_COLUMNS = [
    {
        label: 'Type',
        fieldName: 'recordTypeLabel',
        type: 'text',
        initialWidth: 175
    },
    RECORD_BUTTON_COLUMN,
    {
        label: 'Part / Summary',
        fieldName: 'displayPartSummary',
        type: 'text',
        wrapText: true
    },
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    {
        label: 'Request Notes',
        fieldName: 'notes',
        type: 'text',
        wrapText: true
    },
    PRIMARY_ACTION_COLUMN
];

const WAITING_ON_PARTS_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    {
        label: 'Part',
        fieldName: 'partName',
        type: 'text',
        wrapText: true
    },
    {
        label: 'Qty',
        fieldName: 'quantity',
        type: 'number',
        initialWidth: 75,
        typeAttributes: {
            maximumFractionDigits: 0
        }
    },
    {
        label: 'Work Order',
        type: 'button',
        initialWidth: 145,
        typeAttributes: {
            label: { fieldName: 'relatedRecordNumber' },
            name: 'open_work_order',
            variant: 'base',
            disabled: { fieldName: 'workOrderNavigationDisabled' }
        }
    },
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    {
        label: 'Supplier',
        fieldName: 'supplierName',
        type: 'text'
    },
    STATUS_COLUMN,
    PRIMARY_ACTION_COLUMN
];

const READY_TO_ASSIGN_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    SUBJECT_COLUMN,
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    PRIORITY_COLUMN,
    PRIMARY_ACTION_COLUMN
];

const ASSIGNED_VISITS_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    SUBJECT_COLUMN,
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    PRIORITY_COLUMN,
    TECHNICIAN_COLUMN,
    SCHEDULED_VISIT_COLUMN,
    PRIMARY_ACTION_COLUMN
];

const ACTIVE_REPAIRS_COLUMNS = [
    RECORD_BUTTON_COLUMN,
    SUBJECT_COLUMN,
    ACCOUNT_COLUMN,
    MACHINE_COLUMN,
    PRIORITY_COLUMN,
    STATUS_COLUMN,
    TECHNICIAN_COLUMN,
    PRIMARY_ACTION_COLUMN
];

export default class ManagerOperationsCenter
    extends NavigationMixin(LightningElement) {

    selectedQueueKey = 'newCases';
    operationsData;
    wiredOperationsResult;
    errorMessage;

    isLoading = true;
    isRefreshing = false;

    isFlowModalOpen = false;
    activeFlowApiName;
    activeFlowLabel;
    activeFlowRecordId;

    @wire(getOperationsData)
    wiredOperations(result) {
        this.wiredOperationsResult = result;

        const { data, error } = result;

        this.isLoading = false;
        this.isRefreshing = false;

        if (data) {
            this.operationsData = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.operationsData = undefined;
            this.errorMessage = this.normalizeError(error);
        }
    }

    get columns() {
        switch (this.selectedQueueKey) {
            case 'newCases':
                return CASE_COLUMNS;

            case 'requiresReview':
                return REQUIRES_REVIEW_COLUMNS;

            case 'partsToOrder':
                return PARTS_TO_ORDER_COLUMNS;

            case 'waitingOnParts':
                return WAITING_ON_PARTS_COLUMNS;

            case 'readyToAssign':
                return READY_TO_ASSIGN_COLUMNS;

            case 'assignedVisits':
                return ASSIGNED_VISITS_COLUMNS;

            case 'activeRepairs':
                return ACTIVE_REPAIRS_COLUMNS;

            default:
                return [];
        }
    }

    get queueCards() {
        return QUEUE_CONFIG.map((queue) => {
            const isSelected = queue.key === this.selectedQueueKey;

            return {
                ...queue,
                count: this.operationsData?.[queue.countKey] ?? 0,
                cardClass: isSelected ? 'queue-card queue-card_selected' : 'queue-card',
                ariaPressed: isSelected
            };
        });
    }

    get selectedQueueLabel() {
        return (QUEUE_CONFIG.find((queue) => queue.key === this.selectedQueueKey)?.label ?? 'Operations');
    }

    get selectedQueueDescription() {
        return (QUEUE_CONFIG.find((queue) => queue.key === this.selectedQueueKey)?.description ?? '');
    }

    get selectedRows() {
        const rows = this.operationsData?.[this.selectedQueueKey] ?? [];

        return rows.map((row) => this.normalizeRow(row));
    }

    get hasRows() {
        return this.selectedRows.length > 0;
    }

    get showTable() {
        return (!this.isLoading && !this.errorMessage && this.hasRows);
    }

    get showEmptyState() {
        return (!this.isLoading && !this.errorMessage && !this.hasRows);
    }

    get isBusy() {
        return this.isLoading || this.isRefreshing;
    }

    get flowInputVariables() {
        if (!this.activeFlowRecordId) {
            return [];
        }

        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.activeFlowRecordId
            }
        ];
    }

    normalizeRow(row) {
        const isWorkOrderPart = row.objectApiName === 'Work_Order_Part__c';

        const isPreDispatchWorkOrder = row.rowType === 'WORK_ORDER' && row.status === 'Parts to Order';

        const displaySubject = row.subject || row.workOrderSubject || row.partName || 'No summary provided';

        let displayPartSummary = displaySubject;

        if (isWorkOrderPart) {
            displayPartSummary = row.partName || row.recordNumber || 'Part request';
        } else if (isPreDispatchWorkOrder) {
            displayPartSummary =row.subject || 'Pre-dispatch parts required';
        }

        const hasPrimaryAction = Boolean(row.actionType && row.actionName);

        return {
            ...row,
            displaySubject,
            displayPartSummary,

            recordTypeLabel: row.recordTypeLabel || 'Record',

            recordNumber: row.recordNumber || 'Open',

            relatedRecordNumber: row.relatedRecordNumber || '—',

            accountName: row.accountName || '—',

            assetName: row.assetName || '—',

            partName: row.partName || '—',

            quantity: row.quantity ?? row.quantityNeeded ?? null,

            status: row.status || '—',

            priority: row.priority || '—',

            technicianName: row.technicianName || '—',

            ownerName: row.ownerName || '—',

            notes: row.notes || '—',

            supplierName: row.supplierName || '—',

            supplierPhone: row.supplierPhone || '—',

            orderedByName: row.orderedByName || '—',

            actionLabel: row.actionLabel || 'Open Record',

            recordNavigationDisabled: !row.recordId || !row.objectApiName,

            workOrderNavigationDisabled: !row.workOrderId,

            actionDisabled:
                !hasPrimaryAction ||
                (row.actionType === 'FLOW' &&(!row.flowApiName || !row.actionRecordId)) ||
                (row.actionType === 'NAVIGATE' &&(!row.recordId || !row.objectApiName))
        };
    }

    handleQueueSelect(event) {
        const queueKey = event.currentTarget.dataset.queue;

        if (queueKey) {
            this.selectedQueueKey = queueKey;
        }
    }

    async handleRefresh() {
        if (!this.wiredOperationsResult) {
            return;
        }

        this.isRefreshing = true;
        this.errorMessage = undefined;

        try {
            await refreshApex(this.wiredOperationsResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
            this.showToast('Refresh failed', this.errorMessage, 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;

        const row = event.detail.row;

        if (actionName === 'open_record') {
            this.navigateToRecord(row);
            return;
        }

        if (actionName === 'open_work_order') {
            this.navigateToWorkOrder(row);
            return;
        }

        if (actionName !== 'primary_action') {
            return;
        }

        if (row.actionType === 'FLOW' && row.flowApiName) {
            this.openFlow(row);
            return;
        }

        if (row.actionType === 'NAVIGATE') {
            this.navigateToRecord(row);
            return;
        }

        this.showToast('Unable to run action', 'This row does not have a supported action.','error');
    }

    navigateToRecord(row) {
        if (!row?.recordId || !row?.objectApiName) {
            this.showToast('Unable to open record', 'The record information is incomplete.', 'error');
            return;
        }

        this.navigateToRecordPage(row.recordId, row.objectApiName);
    }

    navigateToWorkOrder(row) {
        if (!row?.workOrderId) {
            this.showToast('Unable to open Work Order', 'The parent Work Order ID is missing.', 'error');
            return;
        }

        this.navigateToRecordPage(row.workOrderId, 'WorkOrder');
    }

    navigateToRecordPage(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    openFlow(row) {
        const flowRecordId = row.actionRecordId;

        if (!row.flowApiName) {
            this.showToast('Unable to launch action', 'The Flow API name is missing.', 'error');
            return;
        }

        if (!flowRecordId) {
            this.showToast('Unable to launch action', 'The required record ID is missing.', 'error');
            return;
        }

        this.activeFlowApiName = row.flowApiName;
        this.activeFlowLabel = row.actionLabel || 'Manager Action';
        this.activeFlowRecordId = flowRecordId;
        this.isFlowModalOpen = true;
    }

    closeFlowModal() {
        this.isFlowModalOpen = false;
        this.activeFlowApiName = undefined;
        this.activeFlowLabel = undefined;
        this.activeFlowRecordId = undefined;
    }

    handleModalClose() {
        this.closeFlowModal();
    }

    async handleFlowStatus(event) {
        const status = event.detail.status;

        if (status !== 'FINISHED' && status !== 'FINISHED_SCREEN') {
            return;
        }

        const completedAction = this.activeFlowLabel || 'Manager action';

        this.closeFlowModal();

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;
            await refreshApex(this.wiredOperationsResult);
            this.showToast('Action completed', `${completedAction} completed successfully.`, 'success');
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
            this.showToast('Refresh failed', this.errorMessage, 'error');
        } finally {
            this.isRefreshing = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({title, message, variant})
        );
    }

    normalizeError(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }

        if (Array.isArray(error)) {
            return error
                .map((item) =>
                    this.normalizeError(item)
                )
                .filter(Boolean)
                .join(', ');
        }

        if (Array.isArray(error.body)) {
            return error.body
                .map((item) => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error.body?.message) {
            return error.body.message;
        }

        if (error.message) {
            return error.message;
        }

        return ('The Manager Operations Center ' + 'could not be loaded.');
    }
}