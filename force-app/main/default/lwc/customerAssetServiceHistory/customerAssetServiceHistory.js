import { LightningElement, api, wire } from 'lwc';
import getServiceHistory from '@salesforce/apex/CustomerAssetServiceHistoryController.getServiceHistory';

const COLUMNS = [
    {
        label: 'Maintenance Date',
        fieldName: 'maintenanceDate',
        type: 'date-local',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        },
        initialWidth: 155
    },
    {
        label: 'Type',
        fieldName: 'maintenanceType',
        type: 'text',
        wrapText: true,
        initialWidth: 150
    },
    {
        label: 'Summary',
        fieldName: 'summary',
        type: 'text',
        wrapText: true
    },
    {
        label: 'Root Cause',
        fieldName: 'rootCause',
        type: 'text',
        wrapText: true
    },
    {
        label: 'Parts Used',
        fieldName: 'partsUsed',
        type: 'text',
        wrapText: true
    },
    {
        label: 'Work Order',
        fieldName: 'workOrderNumber',
        type: 'text',
        initialWidth: 135
    },
    {
        label: 'Labor Hours',
        fieldName: 'laborHours',
        type: 'number',
        typeAttributes: {
            minimumFractionDigits: 0,
            maximumFractionDigits: 2
        },
        initialWidth: 120
    },
    {
        label: 'Status',
        fieldName: 'status',
        type: 'text',
        initialWidth: 145
    }
];

export default class CustomerAssetServiceHistory extends LightningElement {
    _recordId;

    @api title = 'Service History';
    @api recordLimit = 20;

    columns = COLUMNS;
    serviceHistory = [];
    error;
    isLoading = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value !== this._recordId) {
            this._recordId = value;
            this.serviceHistory = [];
            this.error = undefined;
            this.isLoading = Boolean(value);
        }
    }

    get maximumRecords() {
        const parsedLimit = Number.parseInt(this.recordLimit, 10);

        if (Number.isNaN(parsedLimit)) {
            return 20;
        }

        return Math.min(Math.max(parsedLimit, 1), 50);
    }

    get displayTitle() {
        const count = this.serviceHistory.length;

        return count > 0 ? `${this.title} (${count})` : this.title;
    }

    get hasRecords() {
        return this.serviceHistory.length > 0;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get errorMessage() {
        const body = this.error?.body;

        if (Array.isArray(body)) {
            return body
                .map((item) => item.message)
                .filter(Boolean)
                .join(', ');
        }

        return (body?.message || this.error?.message || 'Service history could not be loaded. Contact your MillTrack administrator.');
    }

    @wire(getServiceHistory, { assetId: '$recordId' })
    wiredServiceHistory({ data, error }) {
        if (data) {
            this.serviceHistory = data
                .slice(0, this.maximumRecords)
                .map((entry) => ({ ...entry }));

            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.serviceHistory = [];
            this.error = error;
            this.isLoading = false;
        }
    }
}