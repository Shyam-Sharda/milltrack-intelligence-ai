import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getReviewData from '@salesforce/apex/ManagerReviewWorkOrderController.getReviewData';
import approveWorkOrder from '@salesforce/apex/ManagerReviewWorkOrderController.approveWorkOrder';
import getHistoricalRepairsForLwc from '@salesforce/apex/GetRelevantHistoricalRepairsForCase.getHistoricalRepairsForLwc';
import getCompatibleParts from '@salesforce/apex/ManagerPartCatalogController.getCompatibleParts';

export default class ManagerReviewWorkOrderWizard extends LightningElement {
    @api recordId;

    reviewData;
    historicalResult;

    isLoading = true;
    errorMessage;
    currentStep = 1;

    // Editable AI proposal state. reviewData remains stable record context.
    problemSummary = '';
    recommendedSolution = '';
    recommendedFixSummary = '';
    recommendedTools = [];
    recommendedParts = '';
    technicianNotes = '';
    previousFailure = false;
    proposalPriority = '';
    newToolName = '';

    // Step 3 - Parts to Order state.
    catalogParts = [];
    selectedParts = [];
    partSearchTerm = '';
    isLoadingParts = false;
    partsErrorMessage = '';
    catalogPageSize = 12;
    visibleCatalogPartCount = 12;

    // Regeneration state.
    isRegenerating = false;
    showRegenerationFlow = false;
    showRegenerationConfirmation = false;
    regenerationErrorMessage = '';
    regenerationStartedAt = null;
    minimumRegenerationDisplayMs = 1200;

    // Approval state.
    isApproving = false;
    approvalErrorMessage = '';

    async connectedCallback() {
        await this.loadReview();
    }

    async loadReview() {
        this.isLoading = true;
        this.errorMessage = null;

        try {
            this.reviewData = await getReviewData({ workOrderId: this.recordId });

            this.problemSummary = this.reviewData?.problemSummary || '';
            this.recommendedSolution = this.reviewData?.recommendedSolution || '';
            this.recommendedFixSummary = this.reviewData?.recommendedFixSummary || '';
            this.recommendedTools = this.parseRecommendedTools(this.reviewData?.recommendedTools);
            this.recommendedParts = this.reviewData?.recommendedParts || '';
            this.technicianNotes = this.reviewData?.technicianNotes || '';
            this.previousFailure = this.reviewData?.previousFailure === true;
            this.proposalPriority = this.reviewData?.priority || '';

            await this.loadCompatibleParts();

            if (this.reviewData?.caseId) {
                this.historicalResult = await getHistoricalRepairsForLwc({
                    caseId: this.reviewData.caseId,
                    maxResults: 3
                });
            }
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================
    // Header
    // =========================================================

    get workOrderNumber() {
        return this.reviewData?.workOrderNumber || 'Work Order';
    }

    get priority() {
        return this.proposalPriority || this.reviewData?.priority || 'Not Set';
    }

    get priorityClass() {
        const priority = (this.priority || '').toLowerCase();

        if (priority === 'critical') return 'status-badge priority-critical';
        if (priority === 'high') return 'status-badge priority-high';
        if (priority === 'medium') return 'status-badge priority-medium';

        return 'status-badge priority-low';
    }

    get previousFailureLabel() {
        return this.previousFailure ? 'Previous Failure' : 'No Previous Failure';
    }

    get previousFailureClass() {
        return this.previousFailure
            ? 'status-badge previous-failure'
            : 'status-badge neutral-badge';
    }

    // =========================================================
    // Customer Context
    // =========================================================

    get accountName() {
        return this.reviewData?.accountName || 'Customer not available';
    }

    get contactName() {
        return this.reviewData?.contactName || 'Contact not available';
    }

    get contactTitle() {
        return this.reviewData?.contactTitle || '';
    }

    get contactEmail() {
        return this.reviewData?.contactEmail || '';
    }

    get contactPhone() {
        return this.reviewData?.contactPhone || '';
    }

    get hasContactTitle() {
        return Boolean(this.reviewData?.contactTitle);
    }

    get hasContactEmail() {
        return Boolean(this.reviewData?.contactEmail);
    }

    get hasContactPhone() {
        return Boolean(this.reviewData?.contactPhone);
    }

    // =========================================================
    // Machine Context
    // =========================================================

    get assetName() {
        return this.reviewData?.assetName || 'Machine not available';
    }

    get machineLabel() {
        const manufacturer = this.reviewData?.manufacturer;
        const model = this.reviewData?.model;
        const label = [manufacturer, model].filter(Boolean).join(' ');

        return label || this.assetName;
    }

    get serialNumber() {
        return this.reviewData?.serialNumber || 'Serial not available';
    }

    get machineStatus() {
        return this.reviewData?.machineStatus || 'Status not available';
    }

    get machineStatusClass() {
        const status = (this.machineStatus || '').toLowerCase();

        if (status === 'active') return 'machine-status active-machine';
        if (status === 'needs service') return 'machine-status needs-service';

        return 'machine-status neutral-machine';
    }

    // =========================================================
    // Case Context
    // =========================================================

    get caseNumber() {
        return this.reviewData?.caseNumber || '';
    }

    get caseSubject() {
        return this.reviewData?.caseSubject || '';
    }

    get caseStatus() {
        return this.reviewData?.caseStatus || 'Not Set';
    }

    get caseStatusClass() {
        const status = (this.caseStatus || '').toLowerCase();

        if (status === 'closed') return 'case-status-badge case-status-closed';
        if (status === 'waiting on parts') return 'case-status-badge case-status-waiting';

        if (status === 'working' || status === 'in progress') {
            return 'case-status-badge case-status-working';
        }

        return 'case-status-badge case-status-open';
    }

    get hasCaseNumber() {
        return Boolean(this.reviewData?.caseNumber);
    }

    // =========================================================
    // Historical Repair Intelligence
    // =========================================================

    get hasHistoricalPrecedents() {
        return (this.historicalResult?.precedents?.length || 0) > 0;
    }

    get precedentCount() {
        return this.historicalResult?.precedents?.length || 0;
    }

    get precedentHeading() {
        const count = this.precedentCount;

        if (count === 1) return 'Historical Precedent · 1 similar repair';
        return `Historical Precedent · ${count} similar repairs`;
    }

    get precedents() {
        if (!this.hasHistoricalPrecedents) return [];

        return this.historicalResult.precedents.map((precedent, index) => ({
            ...precedent,
            displayNumber: index + 1,
            machineLabel: [precedent.manufacturer, precedent.model].filter(Boolean).join(' '),
            sameAssetLabel: precedent.sameAsset ? 'Same Asset' : 'Different Asset',
            sameAssetClass: precedent.sameAsset
                ? 'precedent-badge same-asset'
                : 'precedent-badge different-asset',
            hasSuccessfulRepair: Boolean(precedent.successfulRepair),
            hasRootCause: Boolean(precedent.rootCause),
            hasPartsUsed: Boolean(precedent.partsUsed),
            hasTechnicianNotes: Boolean(precedent.technicianNotes),
            hasLaborHours: precedent.laborHours !== null && precedent.laborHours !== undefined
        }));
    }

    get noHistoryMessage() {
        if (!this.historicalResult) {
            return 'Historical repair information is not available.';
        }

        return this.historicalResult.statusMessage ||
            'No relevant historical repair precedent was identified.';
    }

    // =========================================================
    // Regenerate AI Proposal
    // =========================================================

    get regenerationFlowInputs() {
        return [{ name: 'workOrderId', type: 'String', value: this.recordId }];
    }

    get regenerateIconClass() {
        return this.isRegenerating
            ? 'regenerate-icon regenerate-icon-spinning'
            : 'regenerate-icon';
    }

    handleRegenerate() {
        if (this.isRegenerating || !this.recordId) return;
        this.showRegenerationConfirmation = true;
    }

    handleCancelRegeneration() {
        this.showRegenerationConfirmation = false;
    }

    handleConfirmRegeneration() {
        if (this.isRegenerating || !this.recordId) return;

        this.showRegenerationConfirmation = false;
        this.isRegenerating = true;
        this.regenerationStartedAt = Date.now();
        this.regenerationErrorMessage = '';
        this.showRegenerationFlow = false;

        requestAnimationFrame(() => {
            this.showRegenerationFlow = true;
        });
    }

    async handleRegenerationStatus(event) {
        const status = event.detail.status;

        if (status === 'ERROR') {
            this.finishRegenerationWithError();
            return;
        }

        if (status !== 'FINISHED_SCREEN' && status !== 'FINISHED') return;

        try {
            const outputs = event.detail.outputVariables || [];

            const getOutput = name => {
                const output = outputs.find(item => item.name === name);
                return output ? output.value : null;
            };

            this.problemSummary = getOutput('outProblemSummary') ?? this.problemSummary;
            this.recommendedFixSummary = getOutput('outRecommendedFixSummary') ?? this.recommendedFixSummary;
            this.recommendedSolution = getOutput('outRecommendedSolution') ?? this.recommendedSolution;
            this.technicianNotes = getOutput('outTechnicianNotes') ?? this.technicianNotes;

            const regeneratedTools = getOutput('outRecommendedTools');

            if (regeneratedTools !== null && regeneratedTools !== undefined) {
                this.recommendedTools = this.parseRecommendedTools(regeneratedTools);
            }

            this.recommendedParts = getOutput('outRecommendedParts') ?? this.recommendedParts;

            const regeneratedPreviousFailure = getOutput('outPreviousFailure');

            if (regeneratedPreviousFailure !== null && regeneratedPreviousFailure !== undefined) {
                this.previousFailure =
                    regeneratedPreviousFailure === true ||
                    regeneratedPreviousFailure === 'true';
            }

            this.proposalPriority = getOutput('outPriority') ?? this.proposalPriority;

            if (this.reviewData?.caseId) {
                this.historicalResult = await getHistoricalRepairsForLwc({
                    caseId: this.reviewData.caseId,
                    maxResults: 3
                });
            }

            const elapsed = Date.now() - (this.regenerationStartedAt || Date.now());
            const remaining = Math.max(
                0,
                this.minimumRegenerationDisplayMs - elapsed
            );

            if (remaining > 0) {
                await new Promise(resolve => {
                    setTimeout(resolve, remaining);
                });
            }

            this.currentStep = 1;
            this.isRegenerating = false;
            this.showRegenerationFlow = false;
            this.regenerationStartedAt = null;
        } catch (error) {
            this.finishRegenerationWithError(error);
        }
    }

    finishRegenerationWithError(error) {
        this.isRegenerating = false;
        this.showRegenerationFlow = false;
        this.regenerationStartedAt = null;

        this.regenerationErrorMessage = error
            ? this.getErrorMessage(error)
            : 'The AI proposal could not be regenerated. Please try again.';
    }

    // =========================================================
    // Step 2 - Fix & Tools
    // =========================================================

    get recommendedFixSummaryLength() {
        return this.recommendedFixSummary.length;
    }

    get recommendedFixSummaryCounterClass() {
        return this.recommendedFixSummaryLength >= 240
            ? 'character-count character-count-warning'
            : 'character-count';
    }

    get hasRecommendedTools() {
        return this.recommendedTools.length > 0;
    }

    handleRecommendedFixChange(event) {
        this.recommendedFixSummary = event.target.value || '';
    }

    syncRecommendedFixSummaryInput() {
        requestAnimationFrame(() => {
            const input = this.template.querySelector('.fix-summary-input');
            if (input) input.value = this.recommendedFixSummary || '';
        });
    }

    handleNewToolChange(event) {
        this.newToolName = event.target.value || '';
    }

    handleAddTool() {
        const toolName = this.newToolName.trim();

        if (!toolName) return;

        const alreadyExists = this.recommendedTools.some(
            tool => tool.name.toLowerCase() === toolName.toLowerCase()
        );

        if (!alreadyExists) {
            this.recommendedTools = [
                ...this.recommendedTools,
                {
                    id: this.createToolId(toolName),
                    name: toolName
                }
            ];
        }

        this.newToolName = '';
    }

    handleToolKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleAddTool();
        }
    }

    handleRemoveTool(event) {
        const toolId = event.currentTarget.dataset.id;
        this.recommendedTools = this.recommendedTools.filter(
            tool => tool.id !== toolId
        );
    }

    parseRecommendedTools(value) {
        if (!value || value.trim().toLowerCase() === 'none identified') {
            return [];
        }

        return value
            .split(/\r?\n|,|;/)
            .map(tool => tool.trim())
            .filter(Boolean)
            .map(tool => ({
                id: this.createToolId(tool),
                name: tool
            }));
    }

    createToolId(toolName) {
        return toolName
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '');
    }

    // =========================================================
    // Step 3 - Parts to Order
    // =========================================================

    async loadCompatibleParts() {
        const manufacturer = this.reviewData?.manufacturer;
        const model = this.reviewData?.model;

        if (!manufacturer || !model) {
            this.catalogParts = [];
            return;
        }

        this.isLoadingParts = true;
        this.partsErrorMessage = '';

        try {
            const parts = await getCompatibleParts({ manufacturer, model });

            this.visibleCatalogPartCount = this.catalogPageSize;

            this.catalogParts = (parts || []).map(part => ({
                ...part,
                selected: this.selectedParts.some(
                    selected => selected.id === part.id
                )
            }));
        } catch (error) {
            this.partsErrorMessage = this.getErrorMessage(error);
            this.catalogParts = [];
        } finally {
            this.isLoadingParts = false;
        }
    }

    get hasRecommendedParts() {
        const value = (this.recommendedParts || '').trim();

        return Boolean(value) &&
            value.toLowerCase() !== 'none identified';
    }

    get recommendedPartsDisplay() {
        return this.hasRecommendedParts
            ? this.recommendedParts
            : 'None identified';
    }

    get filteredCatalogParts() {
        const searchTerm = (this.partSearchTerm || '').trim().toLowerCase();

        if (!searchTerm) return this.catalogParts;

        return this.catalogParts.filter(part =>
            [
                part.name,
                part.partNumber,
                part.category,
                part.compatibleModel
            ].some(value =>
                (value || '').toLowerCase().includes(searchTerm)
            )
        );
    }

    get visibleCatalogParts() {
        return this.filteredCatalogParts.slice(
            0,
            this.visibleCatalogPartCount
        );
    }

    get hasMoreCatalogParts() {
        return this.visibleCatalogPartCount < this.filteredCatalogParts.length;
    }

    get canShowLessCatalogParts() {
        return this.visibleCatalogPartCount > this.catalogPageSize;
    }

    get catalogDisplayCountLabel() {
        const visibleCount = this.visibleCatalogParts.length;
        const totalCount = this.filteredCatalogParts.length;

        return `Showing ${visibleCount} of ${totalCount}`;
    }

    get hasCatalogParts() {
        return this.filteredCatalogParts.length > 0;
    }

    get hasSelectedParts() {
        return this.selectedParts.length > 0;
    }

    get selectedPartCountLabel() {
        const count = this.selectedParts.length;
        return `${count} selected`;
    }

    handlePartSearchChange(event) {
        this.partSearchTerm = event.target.value || '';
        this.visibleCatalogPartCount = this.catalogPageSize;
    }

    handleShowMoreCatalogParts() {
        this.visibleCatalogPartCount = Math.min(
            this.visibleCatalogPartCount + this.catalogPageSize,
            this.filteredCatalogParts.length
        );
    }

    handleShowLessCatalogParts() {
        this.visibleCatalogPartCount = this.catalogPageSize;
    }

    handlePartSelection(event) {
        const partId = event.currentTarget.dataset.id;
        const isSelected = event.target.checked;
        const part = this.catalogParts.find(item => item.id === partId);

        if (!part) return;

        if (isSelected) {
            if (!this.selectedParts.some(item => item.id === partId)) {
                this.selectedParts = [
                    ...this.selectedParts,
                    {
                        ...part,
                        quantity: 1
                    }
                ];
            }
        } else {
            this.selectedParts = this.selectedParts.filter(
                item => item.id !== partId
            );
        }

        this.syncCatalogSelectionState();
    }

    handlePartQuantityChange(event) {
        const partId = event.currentTarget.dataset.id;
        const parsedQuantity = Number.parseInt(event.target.value, 10);
        const quantity =
            Number.isFinite(parsedQuantity) && parsedQuantity > 0
                ? parsedQuantity
                : 1;

        this.selectedParts = this.selectedParts.map(part =>
            part.id === partId
                ? {
                    ...part,
                    quantity
                }
                : part
        );
    }

    handleRemovePart(event) {
        const partId = event.currentTarget.dataset.id;

        this.selectedParts = this.selectedParts.filter(
            part => part.id !== partId
        );

        this.syncCatalogSelectionState();
    }

    syncCatalogSelectionState() {
        const selectedIds = new Set(
            this.selectedParts.map(part => part.id)
        );

        this.catalogParts = this.catalogParts.map(part => ({
            ...part,
            selected: selectedIds.has(part.id)
        }));
    }

    // =========================================================
    // Step 4 - Approval Summary
    // =========================================================

    get approvalToolCountLabel() {
        const count = this.recommendedTools.length;

        return count === 1
            ? '1 tool'
            : `${count} tools`;
    }

    get approvalPartCountLabel() {
        const count = this.selectedParts.length;

        return count === 1
            ? '1 part selected'
            : `${count} parts selected`;
    }

    get approvalDispatchStatus() {
        return this.hasSelectedParts
            ? 'Parts to Order'
            : 'Ready to Assign';
    }

    get approvalDispatchClass() {
        return this.hasSelectedParts
            ? 'approval-dispatch-status approval-dispatch-parts'
            : 'approval-dispatch-status approval-dispatch-ready';
    }

    get approvalDispatchDescription() {
        return this.hasSelectedParts
            ? 'Required part requests will be created after approval and this Work Order will move to the Parts to Order queue.'
            : 'No parts are required before dispatch. After approval, this Work Order can proceed to technician assignment.';
    }

    get isApproveDisabled() {
        return this.isApproving || this.isRegenerating;
    }

    async handleApproveWorkOrder() {
        if (this.isApproveDisabled || !this.recordId) return;

        this.isApproving = true;
        this.approvalErrorMessage = '';

        try {
            const selectedPartsJson = JSON.stringify(
                this.selectedParts.map(part => ({
                    partCatalogId: part.id,
                    quantity: part.quantity
                }))
            );

            const recommendedTools = this.recommendedTools
                .map(tool => tool.name)
                .join('\n');

            const result = await approveWorkOrder({
                workOrderId: this.recordId,
                problemSummary: this.problemSummary,
                recommendedSolution: this.recommendedSolution,
                recommendedFixSummary: this.recommendedFixSummary,
                recommendedTools,
                recommendedParts: this.recommendedParts,
                previousFailure: this.previousFailure,
                priority: this.priority,
                selectedPartsJson
            });

            if (!result?.success) {
                throw new Error(
                    result?.message ||
                    'The Work Order could not be approved.'
                );
            }

            if (this.reviewData) {
                this.reviewData = {
                    ...this.reviewData,
                    dispatchStatus: result.dispatchStatus
                };
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Work Order Approved',
                    message: result.message,
                    variant: 'success'
                })
            );

            this.dispatchEvent(
                new CustomEvent('approved', {
                    detail: {
                        workOrderId: result.workOrderId,
                        dispatchStatus: result.dispatchStatus,
                        requestedPartCount: result.requestedPartCount,
                        message: result.message
                    }
                })
            );
        } catch (error) {
            this.approvalErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Approval Failed',
                    message: this.approvalErrorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isApproving = false;
        }
    }

    // =========================================================
    // Wizard State
    // =========================================================

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get isStepThree() {
        return this.currentStep === 3;
    }

    get isStepFour() {
        return this.currentStep === 4;
    }

    get stepOneClass() {
        return this.currentStep === 1
            ? 'progress-step active'
            : 'progress-step complete';
    }

    get stepTwoClass() {
        if (this.currentStep === 2) return 'progress-step active';

        return this.currentStep > 2
            ? 'progress-step complete'
            : 'progress-step';
    }

    get stepThreeClass() {
        if (this.currentStep === 3) return 'progress-step active';

        return this.currentStep > 3
            ? 'progress-step complete'
            : 'progress-step';
    }

    get stepFourClass() {
        return this.currentStep === 4
            ? 'progress-step active'
            : 'progress-step';
    }

    handleContinue() {
        this.currentStep = 2;
        this.syncRecommendedFixSummaryInput();
    }

    handleBack() {
        const nextStep = Math.max(1, this.currentStep - 1);

        this.currentStep = nextStep;

        if (nextStep === 2) {
            this.syncRecommendedFixSummaryInput();
        }
    }

    handleContinueToParts() {
        this.currentStep = 3;
    }

    handleContinueToApproval() {
        this.currentStep = 4;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // =========================================================
    // Error Handling
    // =========================================================

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;

        return 'The Work Order review could not be loaded.';
    }
}