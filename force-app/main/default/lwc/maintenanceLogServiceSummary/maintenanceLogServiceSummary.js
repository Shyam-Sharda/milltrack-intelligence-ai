import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import LOG_NAME from '@salesforce/schema/Maintenance_Log__c.Name';
import LOG_DATE from '@salesforce/schema/Maintenance_Log__c.Maintenance_Date__c';
import LOG_TYPE from '@salesforce/schema/Maintenance_Log__c.Maintenance_Type__c';
import LOG_PROBLEM_SUMMARY from '@salesforce/schema/Maintenance_Log__c.Problem_Summary__c';
import LOG_SUMMARY from '@salesforce/schema/Maintenance_Log__c.Summary__c';
import LOG_ROOT_CAUSE from '@salesforce/schema/Maintenance_Log__c.Root_Cause__c';
import LOG_PARTS_USED from '@salesforce/schema/Maintenance_Log__c.Parts_Used__c';
import LOG_LABOR from '@salesforce/schema/Maintenance_Log__c.Labor_Hours__c';
import LOG_RESOLVED from '@salesforce/schema/Maintenance_Log__c.Issue_Resolved__c';
import LOG_FOLLOW_UP from '@salesforce/schema/Maintenance_Log__c.Follow_Up_Required__c';
import LOG_WORK_ORDER from '@salesforce/schema/Maintenance_Log__c.Work_Order__c';
import LOG_ASSET from '@salesforce/schema/Maintenance_Log__c.Asset__c';
import LOG_PERFORMED_BY from '@salesforce/schema/Maintenance_Log__c.Performed_By__c';

import WO_NUMBER from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import WO_DISPATCH from '@salesforce/schema/WorkOrder.Dispatch_Status__c';

import ASSET_NAME from '@salesforce/schema/Asset.Name';
import ASSET_SERIAL from '@salesforce/schema/Asset.Serial_Number__c';
import ASSET_MANUFACTURER from '@salesforce/schema/Asset.Manufacturer__c';
import ASSET_MODEL from '@salesforce/schema/Asset.Model__c';
import ASSET_STATUS from '@salesforce/schema/Asset.Machine_Status__c';

import USER_NAME from '@salesforce/schema/User.Name';

const LOG_FIELDS = [
    LOG_NAME,
    LOG_DATE,
    LOG_TYPE,
    LOG_PROBLEM_SUMMARY,
    LOG_SUMMARY,
    LOG_ROOT_CAUSE,
    LOG_PARTS_USED,
    LOG_LABOR,
    LOG_RESOLVED,
    LOG_FOLLOW_UP,
    LOG_WORK_ORDER,
    LOG_ASSET,
    LOG_PERFORMED_BY
];

const WO_FIELDS = [WO_NUMBER, WO_DISPATCH];
const ASSET_FIELDS = [ASSET_NAME, ASSET_SERIAL, ASSET_MANUFACTURER, ASSET_MODEL, ASSET_STATUS];
const USER_FIELDS = [USER_NAME];

export default class MaintenanceLogServiceSummary extends LightningElement {
    @api recordId;
    @api showRelatedRecordCards = false;
    @api enableServiceOutcomeEditing = false;

    isEditOpen = false;

    summaryField = LOG_SUMMARY;
    rootCauseField = LOG_ROOT_CAUSE;
    partsUsedField = LOG_PARTS_USED;

    // =========================================================
    // Record Data
    // =========================================================

    @wire(getRecord, { recordId: '$recordId', fields: LOG_FIELDS })
    logRecord;

    @wire(getRecord, { recordId: '$workOrderId', fields: WO_FIELDS })
    workOrderRecord;

    @wire(getRecord, { recordId: '$assetId', fields: ASSET_FIELDS })
    assetRecord;

    @wire(getRecord, { recordId: '$performedById', fields: USER_FIELDS })
    performedByRecord;

    // =========================================================
    // Load / Error
    // =========================================================

    get isLoading() {
        return !this.logRecord?.data && !this.logRecord?.error;
    }

    get hasError() {
        return Boolean(this.logRecord?.error);
    }

    get errorMessage() {
        return this.logRecord?.error?.body?.message || 'The Maintenance Log could not be loaded.';
    }

    // =========================================================
    // Related Record IDs
    // =========================================================

    get workOrderId() {
        return getFieldValue(this.logRecord?.data, LOG_WORK_ORDER);
    }

    get assetId() {
        return getFieldValue(this.logRecord?.data, LOG_ASSET);
    }

    get performedById() {
        return getFieldValue(this.logRecord?.data, LOG_PERFORMED_BY);
    }

    // =========================================================
    // Maintenance Log
    // =========================================================

    get logName() {
        return getFieldValue(this.logRecord?.data, LOG_NAME) || 'Maintenance Log';
    }

    get maintenanceType() {
        return getFieldValue(this.logRecord?.data, LOG_TYPE) || 'Service Visit';
    }

    get problemSummary() {
        return getFieldValue(this.logRecord?.data, LOG_PROBLEM_SUMMARY);
    }

    get summary() {
        return getFieldValue(this.logRecord?.data, LOG_SUMMARY);
    }

    get rootCause() {
        return getFieldValue(this.logRecord?.data, LOG_ROOT_CAUSE);
    }

    get partsUsed() {
        return getFieldValue(this.logRecord?.data, LOG_PARTS_USED);
    }

    get laborHours() {
        return getFieldValue(this.logRecord?.data, LOG_LABOR);
    }

    get issueResolved() {
        return getFieldValue(this.logRecord?.data, LOG_RESOLVED) === true;
    }

    get followUpRequired() {
        return getFieldValue(this.logRecord?.data, LOG_FOLLOW_UP) === true;
    }

    // =========================================================
    // Work Order
    // =========================================================

    get workOrderNumber() {
        return getFieldValue(this.workOrderRecord?.data, WO_NUMBER);
    }

    get dispatchStatus() {
        return getFieldValue(this.workOrderRecord?.data, WO_DISPATCH);
    }

    // =========================================================
    // Asset
    // =========================================================

    get assetName() {
        return getFieldValue(this.assetRecord?.data, ASSET_NAME);
    }

    get serialNumber() {
        return getFieldValue(this.assetRecord?.data, ASSET_SERIAL);
    }

    get manufacturer() {
        return getFieldValue(this.assetRecord?.data, ASSET_MANUFACTURER);
    }

    get model() {
        return getFieldValue(this.assetRecord?.data, ASSET_MODEL);
    }

    get machineStatus() {
        return getFieldValue(this.assetRecord?.data, ASSET_STATUS);
    }

    // =========================================================
    // Technician
    // =========================================================

    get performedByName() {
        return getFieldValue(this.performedByRecord?.data, USER_NAME) || 'Technician';
    }

    // =========================================================
    // Display Helpers
    // =========================================================

    get formattedDate() {
        const value = getFieldValue(this.logRecord?.data, LOG_DATE);
        if (!value) return '';

        const [year, month, day] = value.split('-').map(Number);

        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(new Date(year, month - 1, day));
    }

    get machineDetails() {
        return [this.manufacturer, this.model].filter(Boolean).join(' • ');
    }

    get laborLabel() {
        return this.laborHours === null || this.laborHours === undefined
            ? '—'
            : `${this.laborHours} hrs`;
    }

    // =========================================================
    // Visit Type
    // =========================================================

    get normalizedType() {
        return (this.maintenanceType || '').toLowerCase();
    }

    get isRepair() {
        return this.normalizedType === 'repair';
    }

    get isTemporaryRepair() {
        return this.normalizedType.includes('temporary');
    }

    get isPartsRequest() {
        return this.normalizedType === 'inspection' || this.normalizedType.includes('part');
    }

    get maintenanceTypeLabel() {
        if (this.isPartsRequest) return 'Parts Request';
        return this.maintenanceType;
    }

    // =========================================================
    // Visibility
    // =========================================================

    get hasProblemSummary() {
        return Boolean(this.problemSummary?.trim());
    }

    get hasRootCause() {
        return Boolean(this.rootCause?.trim());
    }

    get hasPartsUsed() {
        return Boolean(this.partsUsed?.trim());
    }

    get hasWorkOrder() {
        return Boolean(this.workOrderId && this.workOrderRecord?.data);
    }

    get hasAsset() {
        return Boolean(this.assetId && this.assetRecord?.data);
    }

    get showRelatedContext() {
        return this.showRelatedRecordCards && (this.hasWorkOrder || this.hasAsset);
    }

    // =========================================================
    // Labels
    // =========================================================

    get summaryLabel() {
        return this.isPartsRequest ? 'Visit Summary' : 'Repair Summary';
    }

    get editSummaryLabel() {
        return this.isPartsRequest ? 'Visit Summary' : 'Repair Summary';
    }

    // =========================================================
    // Hero
    // =========================================================

    get heroClass() {
        if (this.isPartsRequest) return 'summary-hero parts-request';
        if (this.issueResolved) return 'summary-hero resolved';
        if (this.followUpRequired) return 'summary-hero follow-up';
        return 'summary-hero neutral';
    }

    get typeIcon() {
        if (this.isPartsRequest) return 'utility:package';
        if (this.issueResolved) return 'utility:success';
        if (this.followUpRequired) return 'utility:warning';
        return 'utility:settings';
    }

    get primaryStatusLabel() {
        if (this.isPartsRequest) return 'Parts Requested';
        if (this.issueResolved) return 'Issue Resolved';
        if (this.followUpRequired) return 'Follow-Up Required';

        return this.dispatchStatus || 'Service Visit';
    }

    get secondaryStatusLabel() {
        if (this.isPartsRequest) return 'Repair Pending Parts';

        if (this.issueResolved && !this.followUpRequired) {
            return 'No Follow-Up Required';
        }

        if (this.followUpRequired) return 'Additional Service Needed';

        return '';
    }

    // =========================================================
    // Edit Service Outcome
    // =========================================================

    handleEditOutcome() {
        this.isEditOpen = true;
    }

    handleCloseEdit() {
        this.isEditOpen = false;
    }

    async handleSaveSuccess() {
        this.isEditOpen = false;

        await notifyRecordUpdateAvailable([
            { recordId: this.recordId }
        ]);

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Service Outcome Updated',
                message: 'The Maintenance Log was updated successfully.',
                variant: 'success'
            })
        );
    }

    handleSaveError(event) {
        const message =
            event.detail?.detail ||
            event.detail?.message ||
            'The Maintenance Log could not be updated.';

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Unable to Save',
                message,
                variant: 'error'
            })
        );
    }

    // =========================================================
    // Navigation
    // =========================================================

    handleWorkOrderOpen() {
        if (!this.hasWorkOrder) return;

        window.open(
            `/lightning/r/WorkOrder/${this.workOrderId}/view`,
            '_self'
        );
    }

    handleAssetOpen() {
        if (!this.hasAsset) return;

        window.open(
            `/lightning/r/Asset/${this.assetId}/view`,
            '_self'
        );
    }
}