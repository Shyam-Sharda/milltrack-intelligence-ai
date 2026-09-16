import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import TITLE from '@salesforce/schema/Service_Manual__c.Name';
import DOCUMENT_TYPE from '@salesforce/schema/Service_Manual__c.Document_Type__c';
import MANUFACTURER from '@salesforce/schema/Service_Manual__c.Manufacturer__c';
import MODEL from '@salesforce/schema/Service_Manual__c.Model__c';
import NOTES from '@salesforce/schema/Service_Manual__c.Notes__c';
import VERSION from '@salesforce/schema/Service_Manual__c.Version__c';

const FIELDS = [TITLE, DOCUMENT_TYPE, MANUFACTURER, MODEL, NOTES, VERSION];

export default class ServiceManualRecordSummary extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS }) manualRecord;

    get isLoading() { return !this.manualRecord?.data && !this.manualRecord?.error; }
    get hasError() { return Boolean(this.manualRecord?.error); }
    get errorMessage() { return this.manualRecord?.error?.body?.message || 'The Service Manual could not be loaded.'; }

    get title() { return getFieldValue(this.manualRecord?.data, TITLE) || 'Service Manual'; }
    get documentType() { return getFieldValue(this.manualRecord?.data, DOCUMENT_TYPE) || 'Manual'; }
    get manufacturer() { return getFieldValue(this.manualRecord?.data, MANUFACTURER) || '—'; }
    get model() { return getFieldValue(this.manualRecord?.data, MODEL) || '—'; }
    get notes() { return getFieldValue(this.manualRecord?.data, NOTES); }
    get version() { return getFieldValue(this.manualRecord?.data, VERSION) || '—'; }

    get machineLabel() { return [this.manufacturer, this.model].filter(value => value && value !== '—').join(' • '); }
    get hasNotes() { return Boolean(this.notes?.trim()); }
}