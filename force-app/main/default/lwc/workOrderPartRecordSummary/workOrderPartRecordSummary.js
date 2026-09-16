import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import WOP_NAME from '@salesforce/schema/Work_Order_Part__c.Name';
import WOP_MACHINE from '@salesforce/schema/Work_Order_Part__c.Machine__c';
import WOP_NOTES from '@salesforce/schema/Work_Order_Part__c.Notes__c';
import WOP_ORDER_STATUS from '@salesforce/schema/Work_Order_Part__c.Order_Status__c';
import WOP_ORDER_URL from '@salesforce/schema/Work_Order_Part__c.Order_URL__c';
import WOP_ORDERED_BY from '@salesforce/schema/Work_Order_Part__c.Ordered_By__c';
import WOP_PART_CATALOG from '@salesforce/schema/Work_Order_Part__c.Part_Catalog__c';
import WOP_QUANTITY from '@salesforce/schema/Work_Order_Part__c.Quantity__c';
import WOP_QUANTITY_NEEDED from '@salesforce/schema/Work_Order_Part__c.Quantity_Needed__c';
import WOP_QUANTITY_USED from '@salesforce/schema/Work_Order_Part__c.Quantity_Used__c';
import WOP_SUPPLIER_NAME from '@salesforce/schema/Work_Order_Part__c.Supplier_Name__c';
import WOP_SUPPLIER_PHONE from '@salesforce/schema/Work_Order_Part__c.Supplier_Phone__c';
import WOP_TECHNICIAN_REQUESTED from '@salesforce/schema/Work_Order_Part__c.Technician_Requested__c';
import WOP_WORK_ORDER from '@salesforce/schema/Work_Order_Part__c.Work_Order__c';

import PART_NAME from '@salesforce/schema/Part_Catalog__c.Name';
import PART_NUMBER from '@salesforce/schema/Part_Catalog__c.Part_Number__c';
import PART_MANUFACTURER from '@salesforce/schema/Part_Catalog__c.Manufacturer__c';
import PART_MODEL from '@salesforce/schema/Part_Catalog__c.Compatible_Model__c';
import PART_CATEGORY from '@salesforce/schema/Part_Catalog__c.Parts_Category__c';

import ASSET_NAME from '@salesforce/schema/Asset.Name';
import ASSET_SERIAL from '@salesforce/schema/Asset.Serial_Number__c';
import ASSET_MANUFACTURER from '@salesforce/schema/Asset.Manufacturer__c';
import ASSET_MODEL from '@salesforce/schema/Asset.Model__c';
import ASSET_STATUS from '@salesforce/schema/Asset.Machine_Status__c';

import WO_NUMBER from '@salesforce/schema/WorkOrder.WorkOrderNumber';
import WO_SUBJECT from '@salesforce/schema/WorkOrder.Subject';
import WO_DISPATCH from '@salesforce/schema/WorkOrder.Dispatch_Status__c';

import USER_NAME from '@salesforce/schema/User.Name';

const WOP_FIELDS = [WOP_NAME, WOP_MACHINE, WOP_NOTES, WOP_ORDER_STATUS, WOP_ORDER_URL, WOP_ORDERED_BY, WOP_PART_CATALOG, WOP_QUANTITY, WOP_QUANTITY_NEEDED, WOP_QUANTITY_USED, WOP_SUPPLIER_NAME, WOP_SUPPLIER_PHONE, WOP_TECHNICIAN_REQUESTED, WOP_WORK_ORDER];
const PART_FIELDS = [PART_NAME, PART_NUMBER, PART_MANUFACTURER, PART_MODEL, PART_CATEGORY];
const ASSET_FIELDS = [ASSET_NAME, ASSET_SERIAL, ASSET_MANUFACTURER, ASSET_MODEL, ASSET_STATUS];
const WO_FIELDS = [WO_NUMBER, WO_SUBJECT, WO_DISPATCH];
const USER_FIELDS = [USER_NAME];

export default class WorkOrderPartRecordSummary extends NavigationMixin(LightningElement) {
    @api recordId;
    @api enableManagerEditing = false;
    @api enableTechnicianEditing = false;

    isManagerEditOpen = false;
    isTechnicianEditOpen = false;

    quantityField = WOP_QUANTITY;
    orderStatusField = WOP_ORDER_STATUS;
    supplierNameField = WOP_SUPPLIER_NAME;
    supplierPhoneField = WOP_SUPPLIER_PHONE;
    orderUrlField = WOP_ORDER_URL;
    orderedByField = WOP_ORDERED_BY;
    notesField = WOP_NOTES;

    @wire(getRecord, { recordId: '$recordId', fields: WOP_FIELDS }) workOrderPartRecord;
    @wire(getRecord, { recordId: '$partCatalogId', fields: PART_FIELDS }) partCatalogRecord;
    @wire(getRecord, { recordId: '$machineId', fields: ASSET_FIELDS }) machineRecord;
    @wire(getRecord, { recordId: '$workOrderId', fields: WO_FIELDS }) workOrderRecord;
    @wire(getRecord, { recordId: '$orderedById', fields: USER_FIELDS }) orderedByRecord;

    get isLoading() { return !this.workOrderPartRecord?.data && !this.workOrderPartRecord?.error; }
    get hasError() { return Boolean(this.workOrderPartRecord?.error); }
    get errorMessage() { return this.workOrderPartRecord?.error?.body?.message || 'The Work Order Part could not be loaded.'; }

    get partCatalogId() { return getFieldValue(this.workOrderPartRecord?.data, WOP_PART_CATALOG); }
    get machineId() { return getFieldValue(this.workOrderPartRecord?.data, WOP_MACHINE); }
    get workOrderId() { return getFieldValue(this.workOrderPartRecord?.data, WOP_WORK_ORDER); }
    get orderedById() { return getFieldValue(this.workOrderPartRecord?.data, WOP_ORDERED_BY); }

    get recordName() { return getFieldValue(this.workOrderPartRecord?.data, WOP_NAME) || 'Work Order Part'; }
    get notes() { return getFieldValue(this.workOrderPartRecord?.data, WOP_NOTES); }
    get orderStatus() { return getFieldValue(this.workOrderPartRecord?.data, WOP_ORDER_STATUS) || 'Not Specified'; }
    get orderUrl() { return getFieldValue(this.workOrderPartRecord?.data, WOP_ORDER_URL); }
    get quantity() { return getFieldValue(this.workOrderPartRecord?.data, WOP_QUANTITY); }
    get quantityNeeded() { return getFieldValue(this.workOrderPartRecord?.data, WOP_QUANTITY_NEEDED); }
    get quantityUsed() { return getFieldValue(this.workOrderPartRecord?.data, WOP_QUANTITY_USED); }
    get supplierName() { return getFieldValue(this.workOrderPartRecord?.data, WOP_SUPPLIER_NAME) || '—'; }
    get supplierPhone() { return getFieldValue(this.workOrderPartRecord?.data, WOP_SUPPLIER_PHONE) || '—'; }
    get technicianRequested() { return getFieldValue(this.workOrderPartRecord?.data, WOP_TECHNICIAN_REQUESTED) === true; }

    get partName() { return getFieldValue(this.partCatalogRecord?.data, PART_NAME) || 'Requested Part'; }
    get partCatalogName() { return this.partName; }
    get partNumber() { return getFieldValue(this.partCatalogRecord?.data, PART_NUMBER) || '—'; }
    get manufacturer() { return getFieldValue(this.partCatalogRecord?.data, PART_MANUFACTURER) || '—'; }
    get compatibleModel() { return getFieldValue(this.partCatalogRecord?.data, PART_MODEL) || '—'; }
    get partCategory() { return getFieldValue(this.partCatalogRecord?.data, PART_CATEGORY) || '—'; }

    get machineName() { return getFieldValue(this.machineRecord?.data, ASSET_NAME) || '—'; }
    get machineSerial() { return getFieldValue(this.machineRecord?.data, ASSET_SERIAL) || '—'; }
    get machineManufacturer() { return getFieldValue(this.machineRecord?.data, ASSET_MANUFACTURER) || '—'; }
    get machineModel() { return getFieldValue(this.machineRecord?.data, ASSET_MODEL) || '—'; }
    get machineStatus() { return getFieldValue(this.machineRecord?.data, ASSET_STATUS); }

    get workOrderNumber() { return getFieldValue(this.workOrderRecord?.data, WO_NUMBER); }
    get workOrderSubject() { return getFieldValue(this.workOrderRecord?.data, WO_SUBJECT); }
    get dispatchStatus() { return getFieldValue(this.workOrderRecord?.data, WO_DISPATCH); }
    get orderedByName() { return getFieldValue(this.orderedByRecord?.data, USER_NAME) || '—'; }

    get hasPartCatalog() { return Boolean(this.partCatalogId && this.partCatalogRecord?.data); }
    get hasMachine() { return Boolean(this.machineId && this.machineRecord?.data); }
    get hasWorkOrder() { return Boolean(this.workOrderId && this.workOrderRecord?.data); }
    get hasOrderUrl() { return Boolean(this.orderUrl); }
    get hasNotes() { return Boolean(this.notes?.trim()); }

    get quantityLabel() { return this.formatQuantity(this.quantity); }
    get quantityNeededLabel() { return this.formatQuantity(this.quantityNeeded); }
    get quantityUsedLabel() { return this.formatQuantity(this.quantityUsed); }
    get requestedLabel() { return this.technicianRequested ? 'Yes' : 'No'; }

    get orderStatusLabel() { return this.orderStatus; }

    get orderStatusClass() {
        const value = (this.orderStatus || '').toLowerCase();

        if (value.includes('received') || value.includes('delivered') || value.includes('available')) {
            return 'status-pill status-success';
        }

        if (value.includes('backorder') || value.includes('cancel') || value.includes('unavailable')) {
            return 'status-pill status-danger';
        }

        if (value.includes('pending') || value.includes('request') || value.includes('await')) {
            return 'status-pill status-warning';
        }

        return 'status-pill status-blue';
    }

    get technicianRequestLabel() {
        return this.technicianRequested ? 'Technician Requested' : 'Standard Request';
    }

    get technicianRequestClass() {
        return this.technicianRequested ? 'request-pill request-tech' : 'request-pill request-standard';
    }

    get showManagerEditButton() { return this.enableManagerEditing; }
    get showTechnicianNotesButton() { return this.enableTechnicianEditing; }

    formatQuantity(value) {
        if (value === null || value === undefined) return '—';
        return Number(value).toLocaleString('en-US', { maximumFractionDigits: 2 });
    }

    openManagerEditModal() { this.isManagerEditOpen = true; }
    openTechnicianNotesModal() { this.isTechnicianEditOpen = true; }
    handleCloseManagerEdit() { this.isManagerEditOpen = false; }
    handleCloseTechnicianEdit() { this.isTechnicianEditOpen = false; }

    async handleManagerSaveSuccess() {
        this.isManagerEditOpen = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

        this.dispatchEvent(new ShowToastEvent({
            title: 'Work Order Part Updated',
            message: 'Ordering details were saved successfully.',
            variant: 'success'
        }));
    }

    async handleTechnicianSaveSuccess() {
        this.isTechnicianEditOpen = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

        this.dispatchEvent(new ShowToastEvent({
            title: 'Technician Notes Updated',
            message: 'Your notes were saved successfully.',
            variant: 'success'
        }));
    }

    handleSaveError(event) {
        const message = event.detail?.detail || event.detail?.message || 'The Work Order Part could not be updated.';

        this.dispatchEvent(new ShowToastEvent({
            title: 'Unable to Save',
            message,
            variant: 'error'
        }));
    }

    handlePartCatalogOpen() {
        if (!this.hasPartCatalog) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.partCatalogId,
                objectApiName: 'Part_Catalog__c',
                actionName: 'view'
            }
        });
    }

    handleMachineOpen() {
        if (!this.hasMachine) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.machineId,
                objectApiName: 'Asset',
                actionName: 'view'
            }
        });
    }

    handleWorkOrderOpen() {
        if (!this.hasWorkOrder) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.workOrderId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }

    handleOrder() {
        if (!this.orderUrl) return;
        window.open(this.orderUrl, '_blank', 'noopener');
    }
}