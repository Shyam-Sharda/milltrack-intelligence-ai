import { LightningElement, api } from 'lwc';
import startWork from '@salesforce/apex/TechnicianStartWorkController.startWork';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';

export default class TechnicianStartWork extends LightningElement {
    _recordId;
    hasStarted = false;
    isLoading = true;
    isSuccess = false;
    isError = false;
    errorMessage;

    @api
    get recordId() { return this._recordId; }

    set recordId(value) {
        this._recordId = value;
        if (value && !this.hasStarted) { this.hasStarted = true; this.beginWork(); }
    }

    async beginWork() {
        this.isLoading = true; this.isSuccess = false; this.isError = false;

        try {
            await startWork({ workOrderId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.isLoading = false; this.isSuccess = true;
            this.dispatchEvent(new RefreshEvent());
        } catch (error) {
            this.isLoading = false; this.isError = true;
            this.errorMessage = error?.body?.message || 'This Work Order cannot be started right now.';
        }
    }

    async handleDone() {
        if (this.recordId) await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(new RefreshEvent());
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}