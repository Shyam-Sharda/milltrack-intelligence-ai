import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import PART_NAME from '@salesforce/schema/Part_Catalog__c.Name';
import PART_NUMBER from '@salesforce/schema/Part_Catalog__c.Part_Number__c';
import MANUFACTURER from '@salesforce/schema/Part_Catalog__c.Manufacturer__c';
import COMPATIBLE_MODEL from '@salesforce/schema/Part_Catalog__c.Compatible_Model__c';
import PARTS_CATEGORY from '@salesforce/schema/Part_Catalog__c.Parts_Category__c';
import ACTIVE from '@salesforce/schema/Part_Catalog__c.Active__c';
import STOCK_STATUS from '@salesforce/schema/Part_Catalog__c.Stock_Status__c';
import PREFERRED_SUPPLIER from '@salesforce/schema/Part_Catalog__c.Preferred_Supplier__c';
import SUPPLIER_NAME from '@salesforce/schema/Part_Catalog__c.Supplier_Name__c';
import SUPPLIER_PHONE from '@salesforce/schema/Part_Catalog__c.Supplier_Phone__c';
import COST from '@salesforce/schema/Part_Catalog__c.Cost__c';
import ORDER_URL from '@salesforce/schema/Part_Catalog__c.Order_URL__c';
import NOTES from '@salesforce/schema/Part_Catalog__c.Notes__c';
import KEYWORDS from '@salesforce/schema/Part_Catalog__c.Keyword_Aliases__c';

const FIELDS = [PART_NAME, PART_NUMBER, MANUFACTURER, COMPATIBLE_MODEL, PARTS_CATEGORY, ACTIVE, STOCK_STATUS, PREFERRED_SUPPLIER, SUPPLIER_NAME, SUPPLIER_PHONE, COST, ORDER_URL, NOTES, KEYWORDS];

export default class PartCatalogRecordSummary extends LightningElement {
    @api recordId;
    @api enableManagerEditing = false;

    isEditOpen = false;

    partNameField = PART_NAME;
    compatibleModelField = COMPATIBLE_MODEL;
    supplierNameField = SUPPLIER_NAME;
    supplierPhoneField = SUPPLIER_PHONE;
    preferredSupplierField = PREFERRED_SUPPLIER;
    keywordsField = KEYWORDS;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS }) partRecord;

    get isLoading() { return !this.partRecord?.data && !this.partRecord?.error; }
    get hasError() { return Boolean(this.partRecord?.error); }
    get errorMessage() { return this.partRecord?.error?.body?.message || 'The Part Catalog record could not be loaded.'; }

    get partName() { return getFieldValue(this.partRecord?.data, PART_NAME) || 'Catalog Part'; }
    get partNumber() { return getFieldValue(this.partRecord?.data, PART_NUMBER) || '—'; }
    get manufacturer() { return getFieldValue(this.partRecord?.data, MANUFACTURER) || '—'; }
    get compatibleModel() { return getFieldValue(this.partRecord?.data, COMPATIBLE_MODEL) || '—'; }
    get partsCategory() { return getFieldValue(this.partRecord?.data, PARTS_CATEGORY) || '—'; }
    get active() { return getFieldValue(this.partRecord?.data, ACTIVE) === true; }
    get stockStatus() { return getFieldValue(this.partRecord?.data, STOCK_STATUS) || 'Not Specified'; }
    get preferredSupplier() { return getFieldValue(this.partRecord?.data, PREFERRED_SUPPLIER) || '—'; }
    get supplierName() { return getFieldValue(this.partRecord?.data, SUPPLIER_NAME) || '—'; }
    get supplierPhone() { return getFieldValue(this.partRecord?.data, SUPPLIER_PHONE) || '—'; }
    get cost() { return getFieldValue(this.partRecord?.data, COST); }
    get orderUrl() { return getFieldValue(this.partRecord?.data, ORDER_URL); }
    get notes() { return getFieldValue(this.partRecord?.data, NOTES); }
    get keywords() { return getFieldValue(this.partRecord?.data, KEYWORDS); }

    get hasOrderUrl() { return Boolean(this.orderUrl); }
    get hasNotes() { return Boolean(this.notes?.trim()); }
    get hasKeywords() { return Boolean(this.keywords?.trim()); }
    get activeLabel() { return this.active ? 'Active' : 'Inactive'; }
    get activeClass() { return this.active ? 'status-pill status-active' : 'status-pill status-inactive'; }

    get stockClass() {
        const value = (this.stockStatus || '').toLowerCase();
        if (value.includes('in stock') || value === 'available') return 'status-pill status-stock';
        if (value.includes('low')) return 'status-pill status-low';
        if (value.includes('out') || value.includes('unavailable')) return 'status-pill status-out';
        return 'status-pill status-blue';
    }

    get costLabel() {
        if (this.cost === null || this.cost === undefined) return '—';
        return new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD' }).format(this.cost);
    }

    handleEdit() { this.isEditOpen = true; }
    handleCloseEdit() { this.isEditOpen = false; }

    async handleSaveSuccess() {
        this.isEditOpen = false;
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

        this.dispatchEvent(new ShowToastEvent({
            title: 'Part Catalog Updated',
            message: 'The part information was updated successfully.',
            variant: 'success'
        }));
    }

    handleSaveError(event) {
        const message = event.detail?.detail || event.detail?.message || 'The Part Catalog record could not be updated.';

        this.dispatchEvent(new ShowToastEvent({
            title: 'Unable to Save',
            message,
            variant: 'error'
        }));
    }

    handleOrder() {
        if (!this.orderUrl) return;
        window.open(this.orderUrl, '_blank', 'noopener');
    }
}