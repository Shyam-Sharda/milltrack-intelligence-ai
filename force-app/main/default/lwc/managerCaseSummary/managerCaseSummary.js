import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListsInfo, getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const CASE_FIELDS = [
    'Case.CaseNumber',
    'Case.Subject',
    'Case.Status',
    'Case.Priority',
    'Case.Origin',
    'Case.Description',
    'Case.Error_Code__c',
    'Case.AI_Troubleshooting_Summary__c',
    'Case.Recommended_Solution__c',
    'Case.Recommended_Parts__c',
    'Case.AccountId',
    'Case.ContactId',
    'Case.AssetId',
    'Case.OwnerId',
    'Case.CreatedDate',
    'Case.ClosedDate',
    'Case.LastModifiedDate',
    'Case.IsClosed',
    'Case.SLA_Due_Date__c'
];

const OPTIONAL_FIELDS = [
    'Case.Account.Name',
    'Case.Contact.Name',
    'Case.Contact.Phone',
    'Case.Contact.Email',
    'Case.Asset.Name',
    'Case.Asset.Manufacturer__c',
    'Case.Asset.Model__c',
    'Case.Asset.Serial_Number__c',
    'Case.Asset.Machine_Status__c',
    'Case.Asset.Warranty_Start_Date__c',
    'Case.Asset.Warranty_End_Date__c',
    'Case.Owner.Name'
];

const WORK_ORDER_FIELDS = [
    'WorkOrder.WorkOrderNumber',
    'WorkOrder.Subject',
    'WorkOrder.Dispatch_Status__c',
    'WorkOrder.Priority',
    'WorkOrder.CreatedDate',
    'WorkOrder.Scheduled_Visit__c',
    'WorkOrder.Work_Started_Date_Time__c',
    'WorkOrder.Work_Ended_Date_Time__c'
];

const CASE_HISTORY_FIELDS = [
    'CaseHistory.CreatedDate',
    'CaseHistory.CreatedBy.Name',
    'CaseHistory.Field',
    'CaseHistory.OldValue',
    'CaseHistory.NewValue'
];

const CASE_COMMENT_FIELDS = [
    'CaseComment.CreatedDate',
    'CaseComment.CreatedBy.Name',
    'CaseComment.CommentBody'
];

const EMAIL_FIELDS = [
    'EmailMessage.CreatedDate',
    'EmailMessage.Subject',
    'EmailMessage.Incoming'
];

const EMAIL_OPTIONAL_FIELDS = [
    'EmailMessage.FromName',
    'EmailMessage.FromAddress',
    'EmailMessage.TextBody'
];

export default class ManagerCaseSummary extends NavigationMixin(LightningElement) {
    @api recordId;

    caseRecord;
    errorMessage;

    workOrders = [];
    workOrderActivities = [];
    caseHistoryActivities = [];
    caseCommentActivities = [];
    emailActivities = [];

    workOrderCount = 0;

    workOrdersRelatedListId;
    caseHistoryRelatedListId;
    caseCommentsRelatedListId;
    emailsRelatedListId;

    now = Date.now();
    timer;
    isActivityExpanded = true;

    connectedCallback() {
        this.timer = window.setInterval(() => {
            this.now = Date.now();
        }, 60000);
    }

    disconnectedCallback() {
        if (this.timer) {
            window.clearInterval(this.timer);
        }
    }

    /* =========================================================
       Case Record
       ========================================================= */

    @wire(getRecord, {
        recordId: '$recordId',
        fields: CASE_FIELDS,
        optionalFields: OPTIONAL_FIELDS
    })
    wiredCase({ data, error }) {
        if (data) {
            this.caseRecord = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.caseRecord = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    /* =========================================================
       Related List Discovery
       ========================================================= */

    @wire(getRelatedListsInfo, { parentObjectApiName: 'Case' })
    wiredRelatedLists({ data }) {
        if (!data) return;

        const lists = data.relatedLists || [];

        this.workOrdersRelatedListId = this.findRelatedListId(lists, ['work orders']);
        this.caseHistoryRelatedListId = this.findRelatedListId(lists, ['case history', 'history']);
        this.caseCommentsRelatedListId = this.findRelatedListId(lists, ['case comments', 'comments']);
        this.emailsRelatedListId = this.findRelatedListId(lists, ['emails', 'email messages']);
    }

    /* =========================================================
       Work Orders + Work Order Activity
       ========================================================= */

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$workOrdersRelatedListId',
        fields: WORK_ORDER_FIELDS,
        pageSize: 10
    })
    wiredWorkOrders({ data }) {
        if (!data) {
            this.workOrders = [];
            this.workOrderActivities = [];
            this.workOrderCount = 0;
            return;
        }

        const records = data.records || [];
        const activities = [];

        this.workOrderCount = data.count ?? records.length;

        this.workOrders = records.map(record => {
            const status = this.relatedValue(record, 'Dispatch_Status__c', 'No Status');

            return {
                id: record.id,
                number: this.relatedValue(record, 'WorkOrderNumber', 'Work Order'),
                subject: this.relatedValue(record, 'Subject', 'No subject'),
                priority: this.relatedValue(record, 'Priority', 'No Priority'),
                status,
                statusClass: this.workOrderStatusClass(status),
                url: this.recordUrl('WorkOrder', record.id)
            };
        });

        records.forEach(record => {
            const number = this.relatedValue(record, 'WorkOrderNumber', 'Work Order');
            const created = this.relatedRawValue(record, 'CreatedDate');
            const scheduled = this.relatedRawValue(record, 'Scheduled_Visit__c');
            const started = this.relatedRawValue(record, 'Work_Started_Date_Time__c');
            const ended = this.relatedRawValue(record, 'Work_Ended_Date_Time__c');

            if (created) {
                activities.push({
                    id: `wo-created-${record.id}`,
                    timestamp: created,
                    dateLabel: this.formatDateTime(created),
                    typeLabel: 'WORK ORDER',
                    title: `${number} Created`,
                    detail: 'A Work Order was created for this service Case.',
                    author: 'MillTrack',
                    icon: 'utility:work_order_type',
                    markerClass: 'activity-marker work-order-marker'
                });
            }

            if (scheduled) {
                activities.push({
                    id: `wo-scheduled-${record.id}`,
                    timestamp: scheduled,
                    dateLabel: this.formatDateTime(scheduled),
                    typeLabel: 'WORK ORDER',
                    title: `${number} Scheduled`,
                    detail: `Service visit scheduled for ${this.formatDateTime(scheduled)}.`,
                    author: 'MillTrack',
                    icon: 'utility:event',
                    markerClass: 'activity-marker work-order-marker'
                });
            }

            if (started) {
                activities.push({
                    id: `wo-started-${record.id}`,
                    timestamp: started,
                    dateLabel: this.formatDateTime(started),
                    typeLabel: 'WORK ORDER',
                    title: `${number} Work Started`,
                    detail: 'Technician work began on this service visit.',
                    author: 'MillTrack',
                    icon: 'utility:play',
                    markerClass: 'activity-marker work-order-marker'
                });
            }

            if (ended) {
                activities.push({
                    id: `wo-ended-${record.id}`,
                    timestamp: ended,
                    dateLabel: this.formatDateTime(ended),
                    typeLabel: 'WORK ORDER',
                    title: `${number} Work Completed`,
                    detail: 'Technician work was completed for this service visit.',
                    author: 'MillTrack',
                    icon: 'utility:check',
                    markerClass: 'activity-marker work-order-marker'
                });
            }
        });

        this.workOrderActivities = activities;
    }

    /* =========================================================
       Case History
       ========================================================= */

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$caseHistoryRelatedListId',
        fields: CASE_HISTORY_FIELDS,
        pageSize: 20
    })
    wiredCaseHistory({ data }) {
        if (!data) {
            this.caseHistoryActivities = [];
            return;
        }

        this.caseHistoryActivities = (data.records || []).map(record => {
            const field = this.relatedValue(record, 'Field', 'Case');
            const oldValue = this.relatedValue(record, 'OldValue', '');
            const newValue = this.relatedValue(record, 'NewValue', '');
            const author = this.relatedValue(record, 'CreatedBy.Name', 'Salesforce');

            return {
                id: `history-${record.id}`,
                timestamp: this.relatedRawValue(record, 'CreatedDate'),
                dateLabel: this.formatDateTime(this.relatedRawValue(record, 'CreatedDate')),
                typeLabel: 'CASE UPDATE',
                title: this.historyTitle(field),
                detail: this.historyDetail(field, oldValue, newValue),
                author,
                icon: 'utility:edit',
                markerClass: 'activity-marker history-marker'
            };
        });
    }

    /* =========================================================
       Case Comments
       ========================================================= */

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$caseCommentsRelatedListId',
        fields: CASE_COMMENT_FIELDS,
        pageSize: 20
    })
    wiredCaseComments({ data }) {
        if (!data) {
            this.caseCommentActivities = [];
            return;
        }

        this.caseCommentActivities = (data.records || []).map(record => ({
            id: `comment-${record.id}`,
            timestamp: this.relatedRawValue(record, 'CreatedDate'),
            dateLabel: this.formatDateTime(this.relatedRawValue(record, 'CreatedDate')),
            typeLabel: 'CASE COMMENT',
            title: 'Comment Added',
            detail: this.relatedValue(record, 'CommentBody', 'No comment text'),
            author: this.relatedValue(record, 'CreatedBy.Name', 'Salesforce User'),
            icon: 'utility:comments',
            markerClass: 'activity-marker comment-marker'
        }));
    }

    /* =========================================================
       Email Activity
       ========================================================= */

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: '$emailsRelatedListId',
        fields: EMAIL_FIELDS,
        optionalFields: EMAIL_OPTIONAL_FIELDS,
        pageSize: 20
    })
    wiredEmails({ data }) {
        if (!data) {
            this.emailActivities = [];
            return;
        }

        this.emailActivities = (data.records || []).map(record => {
            const incoming = Boolean(this.relatedRawValue(record, 'Incoming'));
            const fromName = this.relatedValue(record, 'FromName', '');
            const fromAddress = this.relatedValue(record, 'FromAddress', '');
            const sender = fromName || fromAddress || (incoming ? 'Customer' : 'MillTrack');
            const body = this.relatedValue(record, 'TextBody', '');

            return {
                id: `email-${record.id}`,
                timestamp: this.relatedRawValue(record, 'CreatedDate'),
                dateLabel: this.formatDateTime(this.relatedRawValue(record, 'CreatedDate')),
                typeLabel: incoming ? 'CUSTOMER EMAIL' : 'OUTBOUND EMAIL',
                title: this.relatedValue(record, 'Subject', 'Email'),
                detail: this.truncateText(body, 220),
                author: sender,
                icon: 'utility:email',
                markerClass: 'activity-marker email-marker'
            };
        });
    }

    /* =========================================================
       General State
       ========================================================= */

    get hasRecord() { return Boolean(this.caseRecord); }
    get isLoading() { return !this.caseRecord && !this.errorMessage; }

    value(field) {
        return this.caseRecord ? getFieldValue(this.caseRecord, field) : null;
    }

    display(value, fallback = '—') {
        return value === null || value === undefined || value === '' ? fallback : value;
    }

    recordUrl(objectName, id) {
        return id ? `/lightning/r/${objectName}/${id}/view` : null;
    }

    /* =========================================================
       Case Hero
       ========================================================= */

    get caseNumber() { return this.display(this.value('Case.CaseNumber')); }
    get subject() { return this.display(this.value('Case.Subject'), 'No subject provided'); }
    get status() { return this.display(this.value('Case.Status'), 'No Status'); }
    get priority() { return this.display(this.value('Case.Priority'), 'No Priority'); }
    get origin() { return this.display(this.value('Case.Origin'), 'Not specified'); }

    get statusClass() {
        const status = this.value('Case.Status');

        if (status === 'Closed') return 'hero-pill status-complete';
        if (status === 'In Progress') return 'hero-pill status-progress';
        if (status === 'Waiting on Parts') return 'hero-pill status-parts';
        if (status === 'Scheduled') return 'hero-pill status-scheduled';
        if (status === 'Follow-Up Required') return 'hero-pill status-warning';
        if (status === 'New') return 'hero-pill status-new';

        return 'hero-pill status-neutral';
    }

    get priorityLabel() {
        return `${this.priority} Priority`;
    }

    get priorityClass() {
        if (this.priority === 'Critical') return 'hero-pill priority-critical';
        if (this.priority === 'High') return 'hero-pill priority-high';
        if (this.priority === 'Medium') return 'hero-pill priority-medium';
        if (this.priority === 'Low') return 'hero-pill priority-low';

        return 'hero-pill status-neutral';
    }

    /* =========================================================
       Customer
       ========================================================= */

    get accountId() { return this.value('Case.AccountId'); }
    get accountName() { return this.display(this.value('Case.Account.Name'), 'No account'); }
    get accountUrl() { return this.recordUrl('Account', this.accountId); }

    get contactId() { return this.value('Case.ContactId'); }
    get contactName() { return this.display(this.value('Case.Contact.Name'), 'No contact'); }
    get contactPhone() { return this.display(this.value('Case.Contact.Phone'), 'No phone number'); }
    get contactEmail() { return this.display(this.value('Case.Contact.Email'), 'No email address'); }
    get contactUrl() { return this.recordUrl('Contact', this.contactId); }

    /* =========================================================
       Asset / Machine
       ========================================================= */

    get assetId() { return this.value('Case.AssetId'); }
    get assetName() { return this.display(this.value('Case.Asset.Name'), 'No machine'); }
    get assetUrl() { return this.recordUrl('Asset', this.assetId); }

    get manufacturer() { return this.value('Case.Asset.Manufacturer__c'); }
    get model() { return this.value('Case.Asset.Model__c'); }

    get machineLabel() {
        return [this.manufacturer, this.model].filter(Boolean).join(' ') || '—';
    }

    get serialNumber() {
        return this.display(this.value('Case.Asset.Serial_Number__c'));
    }

    get machineStatus() {
        return this.display(this.value('Case.Asset.Machine_Status__c'), 'Unknown');
    }

    get warrantyStart() {
        return this.formatDate(this.value('Case.Asset.Warranty_Start_Date__c'));
    }

    get warrantyEnd() {
        return this.formatDate(this.value('Case.Asset.Warranty_End_Date__c'));
    }

    get machineStatusClass() {
        const status = this.value('Case.Asset.Machine_Status__c');

        if (status === 'Active') return 'status-chip machine-active';
        if (status === 'Needs Service') return 'status-chip machine-service';
        if (status === 'Temporary Fix Applied') return 'status-chip machine-temporary';
        if (status === 'Out of Service') return 'status-chip machine-out';

        return 'status-chip machine-neutral';
    }

    /* =========================================================
       Service Request
       ========================================================= */

    get description() {
        return this.display(
            this.value('Case.Description'),
            'No customer-reported description has been recorded.'
        );
    }

    get errorCode() {
        return this.display(
            this.value('Case.Error_Code__c'),
            'No error code reported'
        );
    }

    get aiTroubleshootingSummary() {
        return this.display(
            this.value('Case.AI_Troubleshooting_Summary__c'),
            'No AI troubleshooting summary is available.'
        );
    }

    get recommendedSolution() {
        return this.display(
            this.value('Case.Recommended_Solution__c'),
            'No recommended solution is available.'
        );
    }

    get recommendedParts() {
        return this.display(
            this.value('Case.Recommended_Parts__c'),
            'No recommended parts are currently listed.'
        );
    }

    /* =========================================================
       Case Management
       ========================================================= */

    get ownerName() {
        return this.display(this.value('Case.Owner.Name'), 'No owner');
    }

    get createdDate() {
        return this.formatDateTime(this.value('Case.CreatedDate'));
    }

    get closedDate() {
        return this.formatDateTime(
            this.value('Case.ClosedDate'),
            'Not closed'
        );
    }

    get lastModifiedDate() {
        return this.formatDateTime(this.value('Case.LastModifiedDate'));
    }

    get isClosed() {
        return Boolean(this.value('Case.IsClosed'));
    }

    /* =========================================================
       SLA
       ========================================================= */

    get slaDueRaw() {
        return this.value('Case.SLA_Due_Date__c');
    }

    get slaDueDate() {
        return this.formatDateTime(
            this.slaDueRaw,
            'No SLA due date'
        );
    }

    get slaMillisecondsRemaining() {
        if (!this.slaDueRaw) return null;

        return new Date(this.slaDueRaw).getTime() - this.now;
    }

    get slaHealthLabel() {
        if (this.isClosed) return 'Closed';
        if (this.slaMillisecondsRemaining === null) return 'Unavailable';
        if (this.slaMillisecondsRemaining < 0) return 'Breached';
        if (this.slaMillisecondsRemaining <= 4 * 60 * 60 * 1000) return 'At Risk';

        return 'On Track';
    }

    get slaHealthClass() {
        if (this.isClosed) return 'sla-badge sla-closed';
        if (this.slaMillisecondsRemaining === null) return 'sla-badge sla-neutral';
        if (this.slaMillisecondsRemaining < 0) return 'sla-badge sla-breached';
        if (this.slaMillisecondsRemaining <= 4 * 60 * 60 * 1000) return 'sla-badge sla-risk';

        return 'sla-badge sla-track';
    }

    get slaHeroClass() {
        if (this.isClosed) return 'hero-pill sla-hero-closed';
        if (this.slaMillisecondsRemaining === null) return 'hero-pill status-neutral';
        if (this.slaMillisecondsRemaining < 0) return 'hero-pill sla-hero-breached';
        if (this.slaMillisecondsRemaining <= 4 * 60 * 60 * 1000) return 'hero-pill sla-hero-risk';

        return 'hero-pill sla-hero-track';
    }

    get slaHeroLabel() {
        return `SLA ${this.slaHealthLabel}`;
    }

    get slaTimeLabel() {
        if (this.isClosed) {
            const closed = this.value('Case.ClosedDate');

            return closed
                ? `Closed ${this.formatDateTime(closed)}`
                : 'Case is closed';
        }

        const difference = this.slaMillisecondsRemaining;

        if (difference === null) {
            return 'No SLA deadline available';
        }

        const absolute = Math.abs(difference);
        const hours = Math.floor(absolute / (60 * 60 * 1000));
        const minutes = Math.floor(
            (absolute % (60 * 60 * 1000)) / (60 * 1000)
        );

        if (difference < 0) {
            return `${hours} hr${hours === 1 ? '' : 's'} ${minutes} min overdue`;
        }

        return `${hours} hr${hours === 1 ? '' : 's'} ${minutes} min remaining`;
    }

    /* =========================================================
       Unified Case Activity
       ========================================================= */

    get caseActivities() {
        return [
            ...this.caseHistoryActivities,
            ...this.caseCommentActivities,
            ...this.emailActivities,
            ...this.workOrderActivities
        ]
            .filter(activity => activity.timestamp)
            .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
            .slice(0, 15);
    }

    get hasCaseActivity() {
        return this.caseActivities.length > 0;
    }

    get activityChevronIcon() {
        return this.isActivityExpanded
            ? 'utility:chevronup'
            : 'utility:chevrondown';
    }

    get activityToggleTitle() {
        return this.isActivityExpanded
            ? 'Collapse Case Activity'
            : 'Expand Case Activity';
    }

    toggleCaseActivity() {
        this.isActivityExpanded = !this.isActivityExpanded;
    }

    /* =========================================================
       Work Order Rail
       ========================================================= */

    get hasWorkOrders() {
        return this.workOrders.length > 0;
    }

    get workOrderCountLabel() {
        return `${this.workOrderCount} ${this.workOrderCount === 1 ? 'record' : 'records'}`;
    }

    workOrderStatusClass(status) {
        if (status === 'Completed') return 'related-status related-success';
        if (status === 'In Progress' || status === 'Assigned') return 'related-status related-progress';
        if (status === 'Waiting on Parts' || status === 'Parts to Order') return 'related-status related-blue';
        if (status === 'Temporary Fix') return 'related-status related-warning';

        return 'related-status related-neutral';
    }

    /* =========================================================
       Related Record Helpers
       ========================================================= */

    relatedRawValue(record, path) {
        if (!record || !path) return null;

        const segments = path.split('.');
        let fields = record.fields;
        let field;

        for (let index = 0; index < segments.length; index += 1) {
            field = fields?.[segments[index]];

            if (!field) return null;

            if (index < segments.length - 1) {
                fields = field.value?.fields;
            }
        }

        return field?.value ?? null;
    }

    relatedValue(record, path, fallback = '—') {
        if (!record || !path) return fallback;

        const segments = path.split('.');
        let fields = record.fields;
        let field;

        for (let index = 0; index < segments.length; index += 1) {
            field = fields?.[segments[index]];

            if (!field) return fallback;

            if (index < segments.length - 1) {
                fields = field.value?.fields;
            }
        }

        return this.display(
            field?.displayValue ?? field?.value,
            fallback
        );
    }

    findRelatedListId(lists, labels) {
        const candidates = labels.map(label => label.toLowerCase());

        const match = lists.find(item => {
            const label = (item.label || '').toLowerCase();

            return candidates.some(candidate =>
                label.includes(candidate)
            );
        });

        return match?.relatedListId;
    }

    /* =========================================================
       Activity Helpers
       ========================================================= */

    historyTitle(field) {
        if (!field || field === 'Created.') {
            return 'Case Created';
        }

        return `${this.friendlyFieldName(field)} Updated`;
    }

    historyDetail(field, oldValue, newValue) {
        if (!field || field === 'Created.') {
            return 'The Case was created.';
        }

        const label = this.friendlyFieldName(field);

        if (oldValue && newValue) {
            return `${label} changed from ${oldValue} to ${newValue}.`;
        }

        if (newValue) {
            return `${label} changed to ${newValue}.`;
        }

        return `${label} was updated.`;
    }

    friendlyFieldName(field) {
        const map = {
            Status: 'Status',
            Priority: 'Priority',
            Owner: 'Case Owner',
            OwnerId: 'Case Owner',
            Contact: 'Contact',
            ContactId: 'Contact',
            Asset: 'Asset',
            AssetId: 'Asset',
            Subject: 'Subject'
        };

        return map[field] || field || 'Case';
    }

    truncateText(value, maxLength) {
        if (!value) return '';

        const normalized = value
            .replace(/\s+/g, ' ')
            .trim();

        return normalized.length > maxLength
            ? `${normalized.slice(0, maxLength)}…`
            : normalized;
    }

    /* =========================================================
       Navigation
       ========================================================= */

    navigateToRelationship(relationshipApiName) {
        if (!relationshipApiName) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Related List Unavailable',
                message: 'Salesforce could not resolve this related list for the Case.',
                variant: 'warning'
            }));
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Case',
                relationshipApiName,
                actionName: 'view'
            }
        });
    }

    viewAllWorkOrders() {
        this.navigateToRelationship(
            this.workOrdersRelatedListId
        );
    }

    viewFiles() {
        this.navigateToRelationship(
            'AttachedContentDocuments'
        );
    }

    handleUploadFinished(event) {
        const count = event.detail.files?.length || 0;

        this.dispatchEvent(new ShowToastEvent({
            title: 'Files Uploaded',
            message: `${count} ${count === 1 ? 'file was' : 'files were'} uploaded successfully.`,
            variant: 'success'
        }));
    }

    /* =========================================================
       Formatting
       ========================================================= */

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
        } catch (error) {
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
        } catch (error) {
            return value;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }

        if (Array.isArray(error.body)) {
            return error.body
                .map(item => item.message)
                .join(', ');
        }

        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;

        return 'An unexpected error occurred.';
    }
}