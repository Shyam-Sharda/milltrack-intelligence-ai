import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOperationsData from '@salesforce/apex/ManagerOperationsCenterController.getOperationsData';

const NEW_CASES_CONFIG = {
    key: 'newCases',
    countKey: 'newCasesCount',
    label: 'New Cases',
    description: 'New customer service requests'
};

const QUEUE_CONFIG = [
    {
        key: 'requiresReview',
        countKey: 'requiresReviewCount',
        label: 'Requires Review',
        description: 'AI proposals awaiting manager review',
        colorGroup: 'attention'
    },
    {
        key: 'followUpRequired',
        countKey: 'followUpRequiredCount',
        label: 'Follow-Up Required',
        description: 'Temporary repairs awaiting manager follow-up',
        colorGroup: 'attention'
    },
    {
        key: 'partsToOrder',
        countKey: 'partsToOrderCount',
        label: 'Parts to Order',
        description: 'Parts requiring manager action',
        colorGroup: 'workflow'
    },
    {
        key: 'waitingOnParts',
        countKey: 'waitingOnPartsCount',
        label: 'Waiting on Parts',
        description: 'Ordered or shipped parts awaiting receipt',
        colorGroup: 'workflow'
    },
    {
        key: 'readyToAssign',
        countKey: 'readyToAssignCount',
        label: 'Ready to Assign',
        description: 'Work ready for technician dispatch',
        colorGroup: 'workflow'
    },
    {
        key: 'assignedVisits',
        countKey: 'assignedVisitsCount',
        label: 'Assigned Visits',
        description: 'Scheduled technician visits',
        colorGroup: 'active'
    },
    {
        key: 'activeRepairs',
        countKey: 'activeRepairsCount',
        label: 'Active Repairs',
        description: 'Work currently in progress',
        colorGroup: 'active'
    }
];

const ALL_QUEUE_CONFIG = [NEW_CASES_CONFIG, ...QUEUE_CONFIG];

const PORTAL_TABLE_CONFIG = {
    newCases: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'workOrder', label: 'Work Order', type: 'workOrder', fieldName: 'relatedRecordNumber', sortField: 'relatedRecordNumber', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    requiresReview: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'status', label: 'Status', type: 'text', fieldName: 'status', sortField: 'status', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    followUpRequired: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'status', label: 'Status', type: 'text', fieldName: 'status', sortField: 'status', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    partsToOrder: [
        {
            key: 'workOrder',
            label: 'Work Order',
            type: 'workOrderGroup',
            fieldName: 'displayWorkOrderNumber',
            sortField: 'displayWorkOrderNumber',
            sortable: true
        },
        {
            key: 'type',
            label: 'Type',
            type: 'partSource',
            fieldName: 'displayTypeLabel',
            sortField: 'displayTypeLabel',
            sortable: true
        },
        {
            key: 'wop',
            label: 'WOP',
            type: 'wop',
            fieldName: 'displayWopNumber',
            sortField: 'displayWopNumber',
            sortable: true
        },
        {
            key: 'part',
            label: 'Part',
            type: 'part',
            fieldName: 'partName',
            sortField: 'partName',
            sortable: true
        },
        {
            key: 'partSummary',
            label: 'Part Summary',
            type: 'text',
            fieldName: 'displayPartSummary',
            sortField: 'displayPartSummary',
            sortable: true
        },
        {
            key: 'account',
            label: 'Account',
            type: 'text',
            fieldName: 'accountName',
            sortField: 'accountName',
            sortable: true
        },
        {
            key: 'machine',
            label: 'Machine',
            type: 'text',
            fieldName: 'assetName',
            sortField: 'assetName',
            sortable: true
        },
        {
            key: 'notes',
            label: 'Request Notes',
            type: 'text',
            fieldName: 'notes',
            sortField: 'notes',
            sortable: true
        },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    waitingOnParts: [
        {
            key: 'workOrder',
            label: 'Work Order',
            type: 'workOrderGroup',
            fieldName: 'relatedRecordNumber',
            sortField: 'relatedRecordNumber',
            sortable: true
        },
        {
            key: 'type',
            label: 'Type',
            type: 'partSource',
            fieldName: 'displayTypeLabel',
            sortField: 'displayTypeLabel',
            sortable: true
        },
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'part', label: 'Part', type: 'text', fieldName: 'partName', sortField: 'partName', sortable: true },
        { key: 'quantity', label: 'Qty', type: 'number', fieldName: 'quantity', sortField: 'quantity', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'supplier', label: 'Supplier', type: 'text', fieldName: 'supplierName', sortField: 'supplierName', sortable: true },
        { key: 'status', label: 'Status', type: 'text', fieldName: 'status', sortField: 'status', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    readyToAssign: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    assignedVisits: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'technician', label: 'Technician', type: 'text', fieldName: 'technicianName', sortField: 'technicianName', sortable: true },
        { key: 'visit', label: 'Scheduled Visit', type: 'date', fieldName: 'scheduledVisit', sortField: 'scheduledVisit', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ],

    activeRepairs: [
        { key: 'record', label: 'Record', type: 'record', fieldName: 'recordNumber', sortField: 'recordNumber', sortable: true },
        { key: 'subject', label: 'Subject', type: 'text', fieldName: 'displaySubject', sortField: 'displaySubject', sortable: true },
        { key: 'account', label: 'Account', type: 'text', fieldName: 'accountName', sortField: 'accountName', sortable: true },
        { key: 'machine', label: 'Machine', type: 'text', fieldName: 'assetName', sortField: 'assetName', sortable: true },
        { key: 'priority', label: 'Priority', type: 'text', fieldName: 'priority', sortField: 'priority', sortable: true },
        { key: 'status', label: 'Status', type: 'text', fieldName: 'status', sortField: 'status', sortable: true },
        { key: 'technician', label: 'Technician', type: 'text', fieldName: 'technicianName', sortField: 'technicianName', sortable: true },
        { key: 'action', label: 'Action', type: 'action' }
    ]
};

export default class ManagerOperationsCenter extends NavigationMixin(LightningElement) {
    selectedQueueKey = 'requiresReview';
    operationsData;
    wiredOperationsResult;
    errorMessage;
    sortedBy;

    sortDirection = 'asc';
    workOrderGroupDirection = 'asc';
    hoveredWorkOrderGroupKey;

    isLoading = true;
    isRefreshing = false;

    isFlowModalOpen = false;
    activeFlowApiName;
    activeFlowLabel;
    activeFlowRecordId;

    isReviewWizardOpen = false;
    activeReviewWorkOrderId;
    activeReviewWorkOrderNumber;

    isFollowUpWizardOpen = false;
    activeFollowUpWorkOrderId;

    isOrderPartsWizardOpen = false;
    activeOrderPartsRecordId;
    activeOrderPartsMode = 'work-order';

    isReceivePartsWizardOpen = false;
    activeReceivePartsWorkOrderId;

    isDispatchTechnicianWizardOpen = false;
    activeDispatchWorkOrderId;

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

    // =========================================================
    // Queue Cards / Labels
    // =========================================================

    get queueCards() {
        return QUEUE_CONFIG.map(queue => {
            const isSelected = queue.key === this.selectedQueueKey;
            const groupClass = `queue-card_${queue.colorGroup}`;
            const selectedClass = isSelected ? ' queue-card_selected' : '';

            return {
                ...queue,
                count: this.operationsData?.[queue.countKey] ?? 0,
                cardClass: `queue-card ${groupClass}${selectedClass}`,
                ariaPressed: isSelected
            };
        });
    }

    get selectedQueueLabel() {
        return ALL_QUEUE_CONFIG.find(queue => queue.key === this.selectedQueueKey)?.label ?? 'Operations';
    }

    get selectedQueueDescription() {
        return ALL_QUEUE_CONFIG.find(queue => queue.key === this.selectedQueueKey)?.description ?? '';
    }

    get openServiceCasesCount() {
        return this.operationsData?.openServiceCasesCount ?? 0;
    }

    get newCasesCount() {
        return this.operationsData?.newCasesCount ?? 0;
    }

    get isNewCasesSelected() {
        return this.selectedQueueKey === 'newCases';
    }

    get openCasesSummaryClass() {
        return this.isNewCasesSelected
            ? 'open-cases-summary open-cases-summary_selected'
            : 'open-cases-summary';
    }

    get isWorkOrderGroupedQueue() {
        return this.selectedQueueKey === 'waitingOnParts'
            || this.selectedQueueKey === 'partsToOrder';
    }

    // =========================================================
    // Portal-Style Table
    // =========================================================

    get portalColumns() {
        const columns = PORTAL_TABLE_CONFIG[this.selectedQueueKey] || [];

        return columns.map(column => {
            const isPrimaryWorkOrderGroup =
                this.isWorkOrderGroupedQueue
                && column.type === 'workOrderGroup';

            const isSorted = Boolean(
                column.sortable
                && this.sortedBy === column.sortField
            );

            const showSortIcon = isPrimaryWorkOrderGroup || isSorted;

            const sortDirection = isPrimaryWorkOrderGroup
                ? this.workOrderGroupDirection
                : this.sortDirection;

            return {
                ...column,
                isSorted,
                isPrimaryWorkOrderGroup,
                showSortIcon,
                sortIconName:
                    sortDirection === 'asc'
                        ? 'utility:arrowup'
                        : 'utility:arrowdown',
                headerClass:
                    `portal-table-header portal-table-header_${column.type}`
            };
        });
    }

    get selectedRows() {
        const rows = this.operationsData?.[this.selectedQueueKey] ?? [];
        const normalizedRows = rows.map(row => this.normalizeRow(row));

        if (this.isWorkOrderGroupedQueue) {
            return this.prepareWorkOrderGroupedRows(normalizedRows);
        }

        const sortedRows = this.sortedBy
            ? this.sortRows(
                normalizedRows,
                this.sortedBy,
                this.sortDirection
            )
            : normalizedRows;

        return sortedRows.map(row => ({
            ...row,
            rowClass: 'portal-table-row'
        }));
    }

    get portalRows() {
        const columns = this.portalColumns;

        return this.selectedRows.map(row => ({
            ...row,
            cells: columns.map(column =>
                this.buildPortalCell(row, column)
            )
        }));
    }

    prepareWorkOrderGroupedRows(rows) {
        const groupDirection =
            this.workOrderGroupDirection === 'desc'
                ? -1
                : 1;

        const secondaryField =
            this.sortedBy
            && this.sortedBy !== 'displayWorkOrderNumber'
                ? this.sortedBy
                : 'partName';

        const secondaryDirection =
            this.sortedBy
            && this.sortedBy !== 'displayWorkOrderNumber'
                ? this.sortDirection
                : 'asc';

        const sortedRows = [...rows].sort((a, b) => {
            const workOrderCompare = this.compareStrings(
                a.displayWorkOrderNumber || '',
                b.displayWorkOrderNumber || ''
            );

            if (workOrderCompare !== 0) {
                return workOrderCompare * groupDirection;
            }

            return this.compareRowsByField(
                a,
                b,
                secondaryField,
                secondaryDirection
            );
        });

        const groupCounts = new Map();

        sortedRows.forEach(row => {
            const groupKey =
                row.workOrderId
                || row.displayWorkOrderNumber
                || '';

            groupCounts.set(
                groupKey,
                (groupCounts.get(groupKey) || 0) + 1
            );
        });

        return sortedRows.map((row, index) => {
            const groupKey =
                row.workOrderId
                || row.displayWorkOrderNumber
                || '';

            const previousRow = sortedRows[index - 1];

            const previousGroupKey = previousRow
                ? previousRow.workOrderId
                    || previousRow.displayWorkOrderNumber
                    || ''
                : undefined;

            const showWorkOrderGroupCell =
                index === 0
                || groupKey !== previousGroupKey;

            return {
                ...row,
                rowClass: 'portal-table-row',
                workOrderGroupKey: groupKey,
                showWorkOrderGroupCell,
                workOrderGroupRowSpan:
                    showWorkOrderGroupCell
                        ? groupCounts.get(groupKey)
                        : 1
            };
        });
    }

    buildPortalCell(row, column) {
        const rawValue = column.fieldName
            ? row[column.fieldName]
            : undefined;

        const value = this.isBlankValue(rawValue)
            ? '—'
            : rawValue;

        const key = `${row.recordId}-${column.key}`;
        const isWorkOrderGroup = column.type === 'workOrderGroup';
        const isWop = column.type === 'wop';

        const renderCell =
            !isWorkOrderGroup
            || row.showWorkOrderGroupCell;

        const isHoveredWorkOrderGroup =
            isWorkOrderGroup
            && row.workOrderGroupKey
            && row.workOrderGroupKey === this.hoveredWorkOrderGroupKey;

        return {
            key,
            value,
            type: column.type,
            renderCell,
            rowSpan: isWorkOrderGroup
                ? row.workOrderGroupRowSpan
                : 1,
            cellClass:
                `portal-table-cell portal-table-cell_${column.type}`
                + (
                    isHoveredWorkOrderGroup
                        ? ' portal-table-cell_group-hovered'
                        : ''
                ),
            isText: column.type === 'text',
            isNumber: column.type === 'number',
            isDate:
                column.type === 'date'
                && !this.isBlankValue(rawValue),
            isBlankDate:
                column.type === 'date'
                && this.isBlankValue(rawValue),
            isRecord: column.type === 'record',
            isWop,
            isWorkOrder:
                column.type === 'workOrder'
                || isWorkOrderGroup,
            isPartSource: column.type === 'partSource',
            isPart: column.type === 'part',
            isAction: column.type === 'action',
            sourceBadgeClass: row.partSourceBadgeClass,
            partNumber: row.partNumber || '',
            recordId:
                isWop
                    ? row.wopRecordId
                    : row.recordId,
            recordDisabled:
                isWop
                    ? row.wopNavigationDisabled
                    : row.recordNavigationDisabled,
            workOrderId: row.workOrderId,
            workOrderDisabled: row.workOrderNavigationDisabled,
            actionLabel: row.actionLabel,
            actionDisabled: row.actionDisabled
        };
    }

    sortRows(rows, fieldName, directionName) {
        return [...rows].sort((a, b) =>
            this.compareRowsByField(
                a,
                b,
                fieldName,
                directionName
            )
        );
    }

    compareRowsByField(a, b, fieldName, directionName) {
        const direction = directionName === 'asc' ? 1 : -1;

        let aValue = a[fieldName];
        let bValue = b[fieldName];

        const aBlank = this.isBlankValue(aValue);
        const bBlank = this.isBlankValue(bValue);

        if (aBlank && bBlank) return 0;
        if (aBlank) return 1;
        if (bBlank) return -1;

        if (fieldName === 'priority') {
            const priorityRank = {
                Low: 1,
                Medium: 2,
                High: 3,
                Critical: 4
            };

            aValue = priorityRank[aValue] ?? 0;
            bValue = priorityRank[bValue] ?? 0;
        }

        if (
            typeof aValue === 'number'
            && typeof bValue === 'number'
        ) {
            return (aValue - bValue) * direction;
        }

        if (
            fieldName === 'scheduledVisit'
            || fieldName === 'createdDate'
        ) {
            return (
                new Date(aValue).getTime()
                - new Date(bValue).getTime()
            ) * direction;
        }

        return this.compareStrings(aValue, bValue) * direction;
    }

    compareStrings(aValue, bValue) {
        return String(aValue).localeCompare(
            String(bValue),
            undefined,
            {
                numeric: true,
                sensitivity: 'base'
            }
        );
    }

    isBlankValue(value) {
        return value === null
            || value === undefined
            || value === ''
            || value === '—';
    }

    get hasRows() {
        return this.portalRows.length > 0;
    }

    get showTable() {
        return !this.isLoading
            && !this.errorMessage
            && this.hasRows;
    }

    get showEmptyState() {
        return !this.isLoading
            && !this.errorMessage
            && !this.hasRows;
    }

    get isBusy() {
        return this.isLoading || this.isRefreshing;
    }

    handlePortalSort(event) {
        const fieldName = event.currentTarget.dataset.field;

        if (!fieldName) return;

        if (
            this.isWorkOrderGroupedQueue
            && fieldName === 'displayWorkOrderNumber'
        ) {
            this.workOrderGroupDirection =
                this.workOrderGroupDirection === 'asc'
                    ? 'desc'
                    : 'asc';

            this.sortedBy = 'displayWorkOrderNumber';
            this.sortDirection = this.workOrderGroupDirection;

            return;
        }

        if (this.sortedBy === fieldName) {
            this.sortDirection =
                this.sortDirection === 'asc'
                    ? 'desc'
                    : 'asc';
        } else {
            this.sortedBy = fieldName;
            this.sortDirection = 'asc';
        }
    }

    findSelectedRow(recordId) {
        return this.selectedRows.find(
            row => row.recordId === recordId
        );
    }

    handlePortalRecordOpen(event) {
        const row = this.findSelectedRow(
            event.currentTarget.dataset.recordId
        );

        if (row) this.navigateToRecord(row);
    }

    handlePortalWorkOrderOpen(event) {
        const row = this.findSelectedRow(
            event.currentTarget.dataset.recordId
        );

        if (row) this.navigateToWorkOrder(row);
    }

    handlePortalPrimaryAction(event) {
        const row = this.findSelectedRow(
            event.currentTarget.dataset.recordId
        );

        if (row) this.runPrimaryAction(row);
    }

    // =========================================================
    // Flow Input
    // =========================================================

    get flowInputVariables() {
        if (!this.activeFlowRecordId) return [];

        return [
            {
                name: 'recordId',
                type: 'String',
                value: this.activeFlowRecordId
            }
        ];
    }

    // =========================================================
    // Row Normalization
    // =========================================================

    normalizeRow(row) {
        const isWorkOrderPart =
            row.objectApiName === 'Work_Order_Part__c';

        const isPreDispatchWorkOrder =
            row.rowType === 'WORK_ORDER'
            && row.status === 'Parts to Order';

        const isTechnicianRequest =
            row.rowType === 'TECHNICIAN_REQUESTED_PART'
            || Boolean(row.technicianRequested);

        const displaySubject =
            row.subject
            || row.workOrderSubject
            || row.partName
            || 'No summary provided';

        const displayWorkOrderNumber =
            isPreDispatchWorkOrder
                ? row.recordNumber || '—'
                : row.relatedRecordNumber || '—';

        const displayWopNumber =
            isPreDispatchWorkOrder
                ? row.workOrderPartNumber || '—'
                : (
                    isWorkOrderPart
                        ? row.workOrderPartNumber
                            || row.recordNumber
                            || '—'
                        : '—'
                );

        let displayPartSummary =
            row.partSummary
            || row.workOrderSubject
            || row.subject
            || '—';

        if (isPreDispatchWorkOrder) {
            displayPartSummary =
                row.subject
                || 'Pre-dispatch parts required';
        }

        let displayTypeLabel =
            row.recordTypeLabel || 'Record';

        let partSourceBadgeClass =
            'part-source-badge part-source-badge_required';

        if (isTechnicianRequest) {
            displayTypeLabel = 'Technician Request';

            partSourceBadgeClass =
                'part-source-badge part-source-badge_technician';
        } else if (isPreDispatchWorkOrder) {
            displayTypeLabel = 'Work Order';

            partSourceBadgeClass =
                'part-source-badge part-source-badge_workorder';
        } else if (isWorkOrderPart) {
            displayTypeLabel =
                row.partSourceLabel || 'Required Part';
        }

        const workOrderId =
            row.workOrderId
            || (
                isPreDispatchWorkOrder
                    ? row.recordId
                    : null
            );

        const wopRecordId =
            isPreDispatchWorkOrder
                ? row.partId
                : (
                    isWorkOrderPart
                        ? row.recordId
                        : null
                );

        const hasPrimaryAction = Boolean(
            row.actionType
            && row.actionName
        );

        return {
            ...row,
            displaySubject,
            displayPartSummary,
            displayWorkOrderNumber,
            displayWopNumber,
            displayTypeLabel,
            partSourceBadgeClass,
            workOrderId,
            wopRecordId,
            recordTypeLabel:
                row.recordTypeLabel || 'Record',
            recordNumber:
                row.recordNumber || 'Open',
            relatedRecordNumber:
                row.relatedRecordNumber || '—',
            accountName:
                row.accountName || '—',
            assetName:
                row.assetName || '—',
            partName:
                row.partName || '—',
            partNumber:
                row.partNumber || '',
            quantity:
                row.quantity
                ?? row.quantityNeeded
                ?? null,
            status:
                row.status || '—',
            priority:
                row.priority || '—',
            technicianName:
                row.technicianName || '—',
            ownerName:
                row.ownerName || '—',
            notes:
                row.notes || '—',
            supplierName:
                row.supplierName || '—',
            supplierPhone:
                row.supplierPhone || '—',
            orderedByName:
                row.orderedByName || '—',
            actionLabel:
                row.actionLabel || 'Open Record',
            recordNavigationDisabled:
                !row.recordId
                || !row.objectApiName,
            wopNavigationDisabled:
                !wopRecordId,
            workOrderNavigationDisabled:
                !workOrderId,
            actionDisabled:
                !hasPrimaryAction
                || (
                    row.actionType === 'FLOW'
                    && (
                        !row.flowApiName
                        || !row.actionRecordId
                    )
                )
                || (
                    row.actionType === 'NAVIGATE'
                    && (
                        !row.recordId
                        || !row.objectApiName
                    )
                )
        };
    }

    // =========================================================
    // Queue Selection / Sorting / Refresh
    // =========================================================

    handleViewNewCases() {
        this.selectedQueueKey = 'newCases';
        this.resetSelectedQueueSort();
    }

    handleQueueSelect(event) {
        const queueKey = event.currentTarget.dataset.queue;

        if (!queueKey) return;

        this.selectedQueueKey = queueKey;
        this.resetSelectedQueueSort();
    }

    resetSelectedQueueSort() {
        this.hoveredWorkOrderGroupKey = undefined;

        if (this.isWorkOrderGroupedQueue) {
            this.sortedBy = 'displayWorkOrderNumber';
            this.sortDirection = 'asc';
            this.workOrderGroupDirection = 'asc';

            return;
        }

        this.sortedBy = undefined;
        this.sortDirection = 'asc';
    }

    async handleRefresh() {
        if (!this.wiredOperationsResult) return;

        this.isRefreshing = true;
        this.errorMessage = undefined;

        try {
            await refreshApex(this.wiredOperationsResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Primary Actions
    // =========================================================

    runPrimaryAction(row) {
        if (!row) return;

        if (row.actionName === 'FOLLOW_UP_WORK_ORDER') {
            this.openFollowUpWizard(row);
            return;
        }

        if (row.actionName === 'REVIEW_WORK_ORDER') {
            this.openReviewWizard(row);
            return;
        }

        if (
            row.rowType === 'WORK_ORDER'
            && row.status === 'Parts to Order'
        ) {
            this.openOrderPartsWizard(row);
            return;
        }

        if (
            row.actionName
            === 'ORDER_TECHNICIAN_REQUESTED_PART'
        ) {
            this.openTechnicianRequestedPartWizard(row);
            return;
        }

        if (row.actionName === 'RECEIVE_PARTS') {
            this.openReceivePartsWizard(row);
            return;
        }

        if (row.actionName === 'DISPATCH_TECHNICIAN') {
            this.openDispatchTechnicianWizard(row);
            return;
        }

        if (
            row.actionType === 'FLOW'
            && row.flowApiName
        ) {
            this.openFlow(row);
            return;
        }

        if (row.actionType === 'NAVIGATE') {
            this.navigateToRecord(row);
            return;
        }

        this.showToast(
            'Unable to run action',
            'This row does not have a supported action.',
            'error'
        );
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

        if (actionName === 'primary_action') {
            this.runPrimaryAction(row);
        }
    }

    // =========================================================
    // Review Work Order Wizard
    // =========================================================

    openReviewWizard(row) {
        const workOrderId =
            row?.workOrderId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderId) {
            this.showToast(
                'Unable to open review',
                'The Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.activeReviewWorkOrderId = workOrderId;
        this.activeReviewWorkOrderNumber =
            row?.recordNumber || 'Work Order';

        this.isReviewWizardOpen = true;
    }

    closeReviewWizard() {
        this.isReviewWizardOpen = false;
        this.activeReviewWorkOrderId = undefined;
        this.activeReviewWorkOrderNumber = undefined;
    }

    handleReviewWizardCancel() {
        this.closeReviewWizard();
    }

    async handleReviewApproved(event) {
        const detail = event.detail || {};
        const dispatchStatus = detail.dispatchStatus;

        this.closeReviewWizard();

        if (dispatchStatus === 'Parts to Order') {
            this.selectedQueueKey = 'partsToOrder';
        } else if (
            dispatchStatus === 'Ready_to_Assign'
            || dispatchStatus === 'Ready to Assign'
        ) {
            this.selectedQueueKey = 'readyToAssign';
        }

        this.resetSelectedQueueSort();

        if (!this.wiredOperationsResult) return;

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            await refreshApex(this.wiredOperationsResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Follow-Up Work Order Wizard
    // =========================================================

    openFollowUpWizard(row) {
        const workOrderId =
            row?.workOrderId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderId) {
            this.showToast(
                'Unable to open follow-up',
                'The Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.activeFollowUpWorkOrderId = workOrderId;
        this.isFollowUpWizardOpen = true;
    }

    closeFollowUpWizard() {
        this.isFollowUpWizardOpen = false;
        this.activeFollowUpWorkOrderId = undefined;
    }

    handleFollowUpWizardCancel() {
        this.closeFollowUpWizard();
    }

    async handleFollowUpApproved(event) {
        const detail = event.detail || {};
        const dispatchStatus = detail.dispatchStatus;

        this.closeFollowUpWizard();

        if (dispatchStatus === 'Parts to Order') {
            this.selectedQueueKey = 'partsToOrder';
        } else if (
            dispatchStatus === 'Ready_to_Assign'
            || dispatchStatus === 'Ready to Assign'
        ) {
            this.selectedQueueKey = 'readyToAssign';
        }

        this.resetSelectedQueueSort();

        if (!this.wiredOperationsResult) return;

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            await refreshApex(this.wiredOperationsResult);
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Parts Ordering Wizard
    // =========================================================

    get orderPartsModalLabel() {
        return this.activeOrderPartsMode === 'technician-request'
            ? 'Order Technician Requested Part'
            : 'Order Required Parts';
    }

    get orderPartsCloseTitle() {
        return this.activeOrderPartsMode === 'technician-request'
            ? 'Close technician-requested part ordering'
            : 'Close parts ordering';
    }

    openOrderPartsWizard(row) {
        const workOrderId =
            row?.workOrderId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderId) {
            this.showToast(
                'Unable to open parts ordering',
                'The Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.activeOrderPartsRecordId = workOrderId;
        this.activeOrderPartsMode = 'work-order';
        this.isOrderPartsWizardOpen = true;
    }

    openTechnicianRequestedPartWizard(row) {
        const workOrderPartId =
            row?.partId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderPartId) {
            this.showToast(
                'Unable to open requested part ordering',
                'The Work Order Part ID is missing.',
                'error'
            );

            return;
        }

        this.activeOrderPartsRecordId = workOrderPartId;
        this.activeOrderPartsMode = 'technician-request';
        this.isOrderPartsWizardOpen = true;
    }

    closeOrderPartsWizard() {
        this.isOrderPartsWizardOpen = false;
        this.activeOrderPartsRecordId = undefined;
        this.activeOrderPartsMode = 'work-order';
    }

    handleOrderPartsWizardCancel() {
        this.closeOrderPartsWizard();
    }

    async handleOrderPartsComplete(event) {
        const detail = event.detail || {};
        const workOrderStatus = detail.workOrderStatus;

        this.closeOrderPartsWizard();

        if (workOrderStatus === 'Parts to Order') {
            this.selectedQueueKey = 'partsToOrder';
        } else if (workOrderStatus === 'Waiting on Parts') {
            this.selectedQueueKey = 'waitingOnParts';
        } else if (
            workOrderStatus === 'Ready_to_Assign'
            || workOrderStatus === 'Ready to Assign'
        ) {
            this.selectedQueueKey = 'readyToAssign';
        }

        this.resetSelectedQueueSort();

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            if (this.wiredOperationsResult) {
                await refreshApex(this.wiredOperationsResult);
            }
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Receive Parts Wizard
    // =========================================================

    openReceivePartsWizard(row) {
        const workOrderId =
            row?.workOrderId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderId) {
            this.showToast(
                'Unable to open parts receipt',
                'The parent Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.activeReceivePartsWorkOrderId = workOrderId;
        this.isReceivePartsWizardOpen = true;
    }

    closeReceivePartsWizard() {
        this.isReceivePartsWizardOpen = false;
        this.activeReceivePartsWorkOrderId = undefined;
    }

    handleReceivePartsWizardCancel() {
        this.closeReceivePartsWizard();
    }

    async handleReceivePartsComplete(event) {
        const detail = event.detail || {};
        const workOrderStatus = detail.workOrderStatus;

        this.closeReceivePartsWizard();

        if (workOrderStatus === 'Waiting on Parts') {
            this.selectedQueueKey = 'waitingOnParts';
        } else if (
            workOrderStatus === 'Ready_to_Assign'
            || workOrderStatus === 'Ready to Assign'
        ) {
            this.selectedQueueKey = 'readyToAssign';
        }

        this.resetSelectedQueueSort();

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            if (this.wiredOperationsResult) {
                await refreshApex(this.wiredOperationsResult);
            }
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Dispatch Technician Wizard
    // =========================================================

    openDispatchTechnicianWizard(row) {
        const workOrderId =
            row?.workOrderId
            || row?.actionRecordId
            || row?.recordId;

        if (!workOrderId) {
            this.showToast(
                'Unable to open technician dispatch',
                'The Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.activeDispatchWorkOrderId = workOrderId;
        this.isDispatchTechnicianWizardOpen = true;
    }

    closeDispatchTechnicianWizard() {
        this.isDispatchTechnicianWizardOpen = false;
        this.activeDispatchWorkOrderId = undefined;
    }

    handleDispatchTechnicianWizardCancel() {
        this.closeDispatchTechnicianWizard();
    }

    async handleDispatchTechnicianComplete(event) {
        const detail = event.detail || {};
        const workOrderStatus = detail.workOrderStatus;

        this.closeDispatchTechnicianWizard();

        if (workOrderStatus === 'Assigned') {
            this.selectedQueueKey = 'assignedVisits';
        }

        this.resetSelectedQueueSort();

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            if (this.wiredOperationsResult) {
                await refreshApex(this.wiredOperationsResult);
            }
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    // =========================================================
    // Navigation
    // =========================================================

    navigateToRecord(row) {
        if (!row?.recordId || !row?.objectApiName) {
            this.showToast(
                'Unable to open record',
                'The record information is incomplete.',
                'error'
            );

            return;
        }

        this.navigateToRecordPage(
            row.recordId,
            row.objectApiName
        );
    }

    navigateToWorkOrder(row) {
        if (!row?.workOrderId) {
            this.showToast(
                'Unable to open Work Order',
                'The parent Work Order ID is missing.',
                'error'
            );

            return;
        }

        this.navigateToRecordPage(
            row.workOrderId,
            'WorkOrder'
        );
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

    // =========================================================
    // Legacy / Remaining Manager Flows
    // =========================================================

    openFlow(row) {
        const flowRecordId = row.actionRecordId;

        if (!row.flowApiName) {
            this.showToast(
                'Unable to launch action',
                'The Flow API name is missing.',
                'error'
            );

            return;
        }

        if (!flowRecordId) {
            this.showToast(
                'Unable to launch action',
                'The required record ID is missing.',
                'error'
            );

            return;
        }

        this.activeFlowApiName = row.flowApiName;
        this.activeFlowLabel =
            row.actionLabel || 'Manager Action';

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

        if (
            status !== 'FINISHED'
            && status !== 'FINISHED_SCREEN'
        ) {
            return;
        }

        const completedAction =
            this.activeFlowLabel || 'Manager action';

        this.closeFlowModal();

        try {
            this.isRefreshing = true;
            this.errorMessage = undefined;

            await refreshApex(this.wiredOperationsResult);

            this.showToast(
                'Action completed',
                `${completedAction} completed successfully.`,
                'success'
            );
        } catch (error) {
            this.errorMessage = this.normalizeError(error);

            this.showToast(
                'Refresh failed',
                this.errorMessage,
                'error'
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    handlePortalRowMouseEnter(event) {
        if (!this.isWorkOrderGroupedQueue) return;

        this.hoveredWorkOrderGroupKey =
            event.currentTarget.dataset.workOrderGroup
            || undefined;
    }

    handlePortalRowMouseLeave() {
        if (this.isWorkOrderGroupedQueue) {
            this.hoveredWorkOrderGroupKey = undefined;
        }
    }

    // =========================================================
    // Utilities
    // =========================================================

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    normalizeError(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }

        if (Array.isArray(error)) {
            return error
                .map(item => this.normalizeError(item))
                .filter(Boolean)
                .join(', ');
        }

        if (Array.isArray(error.body)) {
            return error.body
                .map(item => item.message)
                .filter(Boolean)
                .join(', ');
        }

        if (error.body?.message) {
            return error.body.message;
        }

        if (error.message) {
            return error.message;
        }

        return 'The Manager Operations Center could not be loaded.';
    }
}