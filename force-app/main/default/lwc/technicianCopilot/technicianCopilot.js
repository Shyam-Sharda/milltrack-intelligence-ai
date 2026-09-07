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

    get serviceManager() {
        return this.context?.serviceManager;
    }

    get maintenanceLogs() {
        return this.context?.maintenanceLogs ?? [];
    }

    /*
     * Service History:
     * previous Maintenance Logs for this exact Asset.
     */
    get assetMaintenanceHistory() {
        return this.context?.assetMaintenanceHistory ?? [];
    }

    /*
     * Similar Repair Precedents:
     * sanitized successful repairs from different-customer Assets
     * of the same machine model.
     *
     * uiKey is presentation-only because the Apex DTO intentionally
     * does not expose historical record IDs to the LWC.
     */
    get similarRepairPrecedents() {
        const precedents = this.context?.similarRepairPrecedents ?? [];

        return precedents.map((precedent, index) => ({
            ...precedent,
            uiKey: [
                precedent.model ?? 'model',
                precedent.maintenanceDate ?? 'date',
                index
            ].join('-'),
            machineLabel:
                [precedent.manufacturer, precedent.model]
                    .filter(Boolean)
                    .join(' ') || 'Similar Machine'
        }));
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

    /*
     * Recommended_Solution__c may contain both current repair guidance
     * and legacy embedded "Historical precedent" text.
     *
     * Similar Repair Precedents now come from the dedicated sanitized
     * Apex collection, so AI Diagnosis should show only the actionable
     * current repair guidance.
     */
    get detailedRecommendedRepair() {
        const solution = this.workOrder?.recommendedSolution?.trim();

        if (!solution) {
            return '';
        }

        const historicalMatch = /historical\s+precedent\s+\d+/i.exec(
            solution
        );

        const bulletMatch = /(^|\n)\s*[-•]\s+/m.exec(solution);

        const historicalStart = historicalMatch
            ? historicalMatch.index
            : -1;

        const bulletStart = bulletMatch
            ? bulletMatch.index + (bulletMatch[1]?.length ?? 0)
            : -1;

        /*
         * Current MillTrack proposal format:
         *
         * Historical precedent 1...
         * Historical precedent 2...
         *
         * - Inspect...
         * - Verify...
         *
         * Return only the actionable repair portion.
         */
        if (
            historicalStart >= 0 &&
            bulletStart >= 0 &&
            historicalStart < bulletStart
        ) {
            return solution.slice(bulletStart).trim();
        }

        /*
         * Also support a future format where repair instructions
         * appear before the historical precedent section.
         */
        if (
            historicalStart > 0 &&
            bulletStart >= 0 &&
            bulletStart < historicalStart
        ) {
            return solution.slice(0, historicalStart).trim();
        }

        /*
         * If historical precedent text exists but there is no
         * recognizable repair block, do not duplicate that historical
         * text inside AI Diagnosis. Fall back to the concise,
         * manager-approved Recommended Fix Summary.
         */
        if (historicalStart >= 0) {
            return this.workOrder?.recommendedFixSummary?.trim() ?? '';
        }

        /*
         * Older or simpler Work Orders may contain only repair
         * guidance. Preserve the full value in that case.
         */
        return solution;
    }

    get showRecommendedSolution() {
        return Boolean(this.detailedRecommendedRepair);
    }

    get showRecommendedTools() {
        return Boolean(this.summary?.hasRecommendedTools);
    }

    get showAiDiagnosis() {
        return Boolean(
            this.workOrder?.problemSummary ||
            this.workOrder?.description ||
            this.detailedRecommendedRepair ||
            this.workOrder?.aiDispatchSummary ||
            this.workOrder?.dispatchResponse ||
            this.workOrder?.technicianNotes
        );
    }

    get showSimilarRepairPrecedents() {
        return Boolean(
            this.summary?.hasSimilarRepairPrecedents &&
            this.similarRepairPrecedents.length > 0
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
        return Boolean(
            this.account ||
            this.contact ||
            this.caseRecord
        );
    }

    get showWorkOrderDetails() {
        return Boolean(
            this.serviceManager ||
            this.workOrder?.workStartedDateTime ||
            this.workOrder?.workEndedDateTime
        );
    }

    get previousFailureLabel() {
        return this.workOrder?.previousFailure ? 'Yes' : 'No';
    }

    getErrorMessage(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .join(', ');
        }

        return (
            error?.body?.message ||
            error?.message ||
            'The Technician Copilot context could not be loaded.'
        );
    }
}