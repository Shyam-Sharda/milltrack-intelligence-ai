import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';

import LOG_WORK_ORDER from '@salesforce/schema/Maintenance_Log__c.Work_Order__c';
import LOG_ASSET from '@salesforce/schema/Maintenance_Log__c.Asset__c';
import LOG_PERFORMED_BY from '@salesforce/schema/Maintenance_Log__c.Performed_By__c';

import WO_NUMBER from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import WO_SUBJECT from '@salesforce/schema/WorkOrder.Subject';
import WO_PROBLEM from '@salesforce/schema/WorkOrder.Problem_Summary__c';
import WO_DISPATCH from '@salesforce/schema/WorkOrder.Dispatch_Status__c';
import WO_SCHEDULED from '@salesforce/schema/WorkOrder.Scheduled_Visit__c';
import WO_LABOR from '@salesforce/schema/WorkOrder.Labor_Hours__c';

import ASSET_NAME from '@salesforce/schema/Asset.Name';
import ASSET_SERIAL from '@salesforce/schema/Asset.Serial_Number__c';
import ASSET_MANUFACTURER from '@salesforce/schema/Asset.Manufacturer__c';
import ASSET_MODEL from '@salesforce/schema/Asset.Model__c';
import ASSET_STATUS from '@salesforce/schema/Asset.Machine_Status__c';

import USER_NAME from '@salesforce/schema/User.Name';

const LOG_FIELDS = [LOG_WORK_ORDER, LOG_ASSET, LOG_PERFORMED_BY];
const WO_FIELDS = [WO_NUMBER, WO_SUBJECT, WO_PROBLEM, WO_DISPATCH, WO_SCHEDULED, WO_LABOR];
const ASSET_FIELDS = [ASSET_NAME, ASSET_SERIAL, ASSET_MANUFACTURER, ASSET_MODEL, ASSET_STATUS];
const USER_FIELDS = [USER_NAME];

export default class MaintenanceLogManagerContext extends NavigationMixin(LightningElement) {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: LOG_FIELDS }) logRecord;
    @wire(getRecord, { recordId: '$workOrderId', fields: WO_FIELDS }) workOrderRecord;
    @wire(getRecord, { recordId: '$assetId', fields: ASSET_FIELDS }) assetRecord;
    @wire(getRecord, { recordId: '$performedById', fields: USER_FIELDS }) performedByRecord;

    get workOrderId() { return getFieldValue(this.logRecord?.data, LOG_WORK_ORDER); }
    get assetId() { return getFieldValue(this.logRecord?.data, LOG_ASSET); }
    get performedById() { return getFieldValue(this.logRecord?.data, LOG_PERFORMED_BY); }

    get hasWorkOrder() { return Boolean(this.workOrderId && this.workOrderRecord?.data); }
    get hasAsset() { return Boolean(this.assetId && this.assetRecord?.data); }

    get workOrderNumber() { return getFieldValue(this.workOrderRecord?.data, WO_NUMBER); }
    get workOrderSubject() { return getFieldValue(this.workOrderRecord?.data, WO_SUBJECT); }
    get problemSummary() { return getFieldValue(this.workOrderRecord?.data, WO_PROBLEM); }
    get dispatchStatus() { return getFieldValue(this.workOrderRecord?.data, WO_DISPATCH); }
    get scheduledVisit() { return getFieldValue(this.workOrderRecord?.data, WO_SCHEDULED); }
    get workOrderLabor() { return getFieldValue(this.workOrderRecord?.data, WO_LABOR); }
    get technicianName() { return getFieldValue(this.performedByRecord?.data, USER_NAME) || '—'; }

    get assetName() { return getFieldValue(this.assetRecord?.data, ASSET_NAME); }
    get serialNumber() { return getFieldValue(this.assetRecord?.data, ASSET_SERIAL) || '—'; }
    get manufacturer() { return getFieldValue(this.assetRecord?.data, ASSET_MANUFACTURER) || '—'; }
    get model() { return getFieldValue(this.assetRecord?.data, ASSET_MODEL) || '—'; }
    get machineStatus() { return getFieldValue(this.assetRecord?.data, ASSET_STATUS); }

    get scheduledVisitLabel() {
        if (!this.scheduledVisit) return '—';
        return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(this.scheduledVisit));
    }

    get workOrderLaborLabel() { return this.workOrderLabor === null || this.workOrderLabor === undefined ? '—' : `${this.workOrderLabor} hrs`; }

    get workOrderStatusClass() {
        const value = (this.dispatchStatus || '').toLowerCase();
        if (value === 'completed') return 'status-pill status-success';
        if (value === 'temporary fix') return 'status-pill status-warning';
        if (value.includes('part')) return 'status-pill status-blue';
        if (value === 'in progress') return 'status-pill status-progress';
        return 'status-pill status-neutral';
    }

    get machineStatusClass() {
        const value = (this.machineStatus || '').toLowerCase();
        if (value === 'active') return 'status-pill status-success';
        if (value === 'temporary fix applied') return 'status-pill status-warning';
        if (value === 'needs service') return 'status-pill status-danger';
        return 'status-pill status-blue';
    }

    handleWorkOrderOpen() {
        if (!this.workOrderId) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.workOrderId, objectApiName: 'WorkOrder', actionName: 'view' } });
    }

    handleAssetOpen() {
        if (!this.assetId) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.assetId, objectApiName: 'Asset', actionName: 'view' } });
    }
}