import { LightningElement, api, wire } from 'lwc';
import getCopilotContext from '@salesforce/apex/TechnicianCopilotController.getCopilotContext';

export default class TechnicianCopilot extends LightningElement {
    @api recordId;

    context;
    error;

    @wire(getCopilotContext, { workOrderId: '$recordId' })
    wiredCopilotContext({ data, error }) {
        if (data) {
            this.context = data;
            this.error = undefined;
        } else if (error) {
            this.context = undefined;
            this.error = this.getErrorMessage(error);
        }
    }

    get isLoading() {
        return !this.context && !this.error;
    }

    get hasContext() {
        return Boolean(this.context);
    }

    get workOrder() {
        return this.context?.workOrder;
    }

    get asset() {
        return this.context?.asset;
    }

    get account() {
        return this.context?.account;
    }

    get contact() {
        return this.context?.contact;
    }

    get caseRecord() {
        return this.context?.caseRecord;
    }

    get maintenanceLogs() {
        return this.context?.maintenanceLogs ?? [];
    }

    get assetMaintenanceHistory() {
        return this.context?.assetMaintenanceHistory ?? [];
    }

    get workOrderParts() {
        return this.context?.workOrderParts ?? [];
    }

    get summary() {
        return this.context?.summary;
    }

    get showIssueSummary() {
        return Boolean(this.summary?.hasIssueSummary);
    }

    get showRecommendedFixSummary() {
        return Boolean(this.summary?.hasRecommendedFixSummary);
    }

    get showRecommendedSolution() {
        return Boolean(this.summary?.hasRecommendedSolution);
    }

    get showRecommendedTools() {
        return Boolean(this.summary?.hasRecommendedTools);
    }

    get showAiDiagnosis() {
        return Boolean(
            this.workOrder?.problemSummary ||
            this.workOrder?.description ||
            this.workOrder?.recommendedSolution ||
            this.workOrder?.aiDispatchSummary ||
            this.workOrder?.dispatchResponse ||
            this.workOrder?.technicianNotes
        );
    }

    get showRepairProgress() {
        return Boolean(this.summary?.hasCurrentWorkOrderActivity);
    }

    get showServiceHistory() {
        return Boolean(this.summary?.hasAssetMaintenanceHistory);
    }

    get showParts() {
        return Boolean(this.summary?.hasParts);
    }

    get showCustomerInformation() {
        return Boolean(this.account || this.contact || this.caseRecord);
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .join(', ');
        }

        return (error?.body?.message || error?.message || 'The Technician Copilot context could not be loaded.');
    }
}