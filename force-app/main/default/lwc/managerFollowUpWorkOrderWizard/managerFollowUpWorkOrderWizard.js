import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getFollowUpData from '@salesforce/apex/ManagerFollowUpWorkOrderController.getFollowUpData';
import approveFollowUp from '@salesforce/apex/ManagerFollowUpWorkOrderController.approveFollowUp';
import getToolCatalog from '@salesforce/apex/ManagerFollowUpWorkOrderController.getToolCatalog';
import getCompatibleParts from '@salesforce/apex/ManagerPartCatalogController.getCompatibleParts';

export default class ManagerFollowUpWorkOrderWizard extends LightningElement {

    @api recordId;

    followUpData;
    isLoading = true;
    errorMessage;
    currentStep = 1;

    // Step 2 - New follow-up plan.
    recommendedFixSummary = '';
    recommendedTools = [];
    toolCatalog = [];
    selectedToolId = '';
    selectedToolName = '';
    toolSearchTerm = '';
    isToolDropdownOpen = false;
    planErrorMessage = '';

    // Step 3 - Additional parts.
    catalogParts = [];
    selectedParts = [];
    partSearchTerm = '';
    isLoadingParts = false;
    partsErrorMessage = '';
    catalogPageSize = 12;
    visibleCatalogPartCount = 12;

    // Approval.
    isApproving = false;
    approvalErrorMessage = '';

    async connectedCallback() {
        await this.loadFollowUp();
    }

    async loadFollowUp() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            this.followUpData = await getFollowUpData({ workOrderId: this.recordId });

            // Intentionally blank. The manager is creating the NEXT visit plan,
            // not silently carrying forward the previous technician instructions.
            this.recommendedFixSummary = '';
            this.recommendedTools = [];

            await Promise.all([
                this.loadToolCatalog(),
                this.loadCompatibleParts()
            ]);
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadToolCatalog() {
        try {
            this.toolCatalog = await getToolCatalog() || [];
        } catch (error) {
            this.toolCatalog = [];
            throw error;
        }
    }

    // =========================================================
    // Header / Work Order
    // =========================================================

    get workOrderNumber() { return this.followUpData?.workOrderNumber || 'Work Order'; }
    get priority() { return this.followUpData?.priority || 'Not Set'; }
    get dispatchStatus() { return this.followUpData?.dispatchStatus || 'Temporary Fix'; }

    get priorityClass() {
        const priority = (this.priority || '').toLowerCase();

        if (priority === 'critical') return 'status-badge priority-critical';
        if (priority === 'high') return 'status-badge priority-high';
        if (priority === 'medium') return 'status-badge priority-medium';

        return 'status-badge priority-low';
    }

    // =========================================================
    // Customer / Case
    // =========================================================

    get accountName() { return this.followUpData?.accountName || 'Customer not available'; }
    get contactName() { return this.followUpData?.contactName || 'Contact not available'; }
    get contactTitle() { return this.followUpData?.contactTitle || ''; }
    get contactEmail() { return this.followUpData?.contactEmail || ''; }
    get contactPhone() { return this.followUpData?.contactPhone || ''; }
    get hasContactTitle() { return Boolean(this.followUpData?.contactTitle); }
    get hasContactEmail() { return Boolean(this.followUpData?.contactEmail); }
    get hasContactPhone() { return Boolean(this.followUpData?.contactPhone); }

    get caseNumber() { return this.followUpData?.caseNumber || ''; }
    get caseSubject() { return this.followUpData?.caseSubject || 'Case subject not available'; }
    get caseStatus() { return this.followUpData?.caseStatus || 'Not Set'; }
    get hasCaseNumber() { return Boolean(this.followUpData?.caseNumber); }

    get caseStatusClass() {
        const status = (this.caseStatus || '').toLowerCase();

        if (status === 'follow-up required') return 'case-status-badge case-status-follow-up';
        if (status === 'closed') return 'case-status-badge case-status-closed';
        if (status === 'waiting on parts') return 'case-status-badge case-status-waiting';
        if (status === 'working' || status === 'in progress') return 'case-status-badge case-status-working';

        return 'case-status-badge case-status-open';
    }

    // =========================================================
    // Machine
    // =========================================================

    get assetName() { return this.followUpData?.assetName || 'Machine not available'; }

    get machineLabel() {
        const manufacturer = this.followUpData?.manufacturer;
        const model = this.followUpData?.model;

        return [manufacturer, model].filter(Boolean).join(' ') || this.assetName;
    }

    get manufacturer() { return this.followUpData?.manufacturer || ''; }
    get serialNumber() { return this.followUpData?.serialNumber || 'Serial not available'; }
    get machineStatus() { return this.followUpData?.machineStatus || 'Status not available'; }

    get machineStatusClass() {
        const status = (this.machineStatus || '').toLowerCase();

        if (status === 'temporary fix applied') return 'machine-status temporary-machine';
        if (status === 'active') return 'machine-status active-machine';
        if (status === 'needs service') return 'machine-status needs-service';

        return 'machine-status neutral-machine';
    }

    // =========================================================
    // Original Issue / Previous Visit
    // =========================================================

    get problemSummary() { return this.followUpData?.problemSummary || 'Problem Summary not available.'; }
    get maintenanceLogNumber() { return this.followUpData?.maintenanceLogNumber || 'Maintenance Log'; }
    get maintenanceDate() { return this.followUpData?.maintenanceDate; }
    get maintenanceType() { return this.followUpData?.maintenanceType || 'Service Visit'; }
    get technicianName() { return this.followUpData?.technicianName || 'Technician not available'; }
    get laborHours() { return this.followUpData?.laborHours ?? 0; }

    get previousRecommendedFix() {
        return this.followUpData?.previousRecommendedFix || 'No previous Recommended Fix was recorded.';
    }

    get visitSummary() {
        return this.followUpData?.visitSummary || 'No visit summary was recorded.';
    }

    get previousTools() { return this.parseTools(this.followUpData?.previousTools); }
    get hasPreviousTools() { return this.previousTools.length > 0; }

    get visitOutcomeLabel() {
        if (this.followUpData?.followUpRequired) return 'Follow-Up Required';
        if (this.followUpData?.issueResolved) return 'Resolved';

        return 'Unresolved';
    }

    get visitOutcomeClass() {
        if (this.followUpData?.followUpRequired) return 'visit-outcome visit-outcome-follow-up';
        if (this.followUpData?.issueResolved) return 'visit-outcome visit-outcome-resolved';

        return 'visit-outcome visit-outcome-neutral';
    }

    // =========================================================
    // Existing Work Order Parts
    // =========================================================

    get existingParts() { return this.followUpData?.existingParts || []; }
    get hasExistingParts() { return this.existingParts.length > 0; }

    get existingPartCountLabel() {
        const count = this.existingParts.length;
        return count === 1 ? '1 existing part' : `${count} existing parts`;
    }

    get existingPartsView() {
        return this.existingParts.map(part => ({
            ...part,
            statusClass: this.getPartStatusClass(part.status),
            sourceClass: part.technicianRequested
                ? 'part-source-chip part-source-technician'
                : 'part-source-chip part-source-manager',
            hasNotes: Boolean(part.notes)
        }));
    }

    getPartStatusClass(status) {
        const value = (status || '').toLowerCase();

        if (value === 'received' || value === 'installed') return 'existing-part-status existing-part-status-complete';
        if (value === 'ordered' || value === 'shipped') return 'existing-part-status existing-part-status-progress';
        if (value === 'requested') return 'existing-part-status existing-part-status-requested';
        if (value === 'cancelled') return 'existing-part-status existing-part-status-cancelled';

        return 'existing-part-status existing-part-status-neutral';
    }

    // =========================================================
    // Step 2 - Follow-Up Fix / Tools
    // =========================================================

    get recommendedFixSummaryLength() { return this.recommendedFixSummary.length; }

    get recommendedFixSummaryCounterClass() {
        return this.recommendedFixSummaryLength >= 240
            ? 'character-count character-count-warning'
            : 'character-count';
    }

    get hasRecommendedTools() { return this.recommendedTools.length > 0; }

    handleRecommendedFixChange(event) {
        this.recommendedFixSummary = event.target.value || '';
        if (this.recommendedFixSummary.trim()) this.planErrorMessage = '';
    }

    syncRecommendedFixSummaryInput() {
        requestAnimationFrame(() => {
            const input = this.template.querySelector('.fix-summary-input');
            if (input) input.value = this.recommendedFixSummary || '';
        });
    }

    get availableToolOptions() {
        const selectedIds = new Set(this.recommendedTools.map(tool => tool.id));
        const searchTerm = (this.toolSearchTerm || '').trim().toLowerCase();

        return this.toolCatalog.filter(tool => {
            if (selectedIds.has(tool.id)) return false;
            if (!searchTerm) return true;

            return (tool.name || '').toLowerCase().includes(searchTerm);
        });
    }

    get hasAvailableToolOptions() { return this.availableToolOptions.length > 0; }
    get toolPickerLabel() { return this.selectedToolName || 'Select a tool...'; }

    get toolPickerClass() {
        return this.isToolDropdownOpen ? 'tool-picker tool-picker-open' : 'tool-picker';
    }

    get toolPickerChevronClass() {
        return this.isToolDropdownOpen
            ? 'tool-picker-chevron tool-picker-chevron-open'
            : 'tool-picker-chevron';
    }

    get isAddToolDisabled() { return !this.selectedToolId; }

    handleToggleToolDropdown() {
        this.isToolDropdownOpen = !this.isToolDropdownOpen;

        if (this.isToolDropdownOpen) {
            this.toolSearchTerm = '';

            requestAnimationFrame(() => {
                const searchInput = this.template.querySelector('.tool-picker-search-input');
                if (searchInput) searchInput.focus();
            });
        }
    }

    handleToolSearchChange(event) {
        this.toolSearchTerm = event.target.value || '';
    }

    handleToolSearchKeyDown(event) {
        if (event.key !== 'Escape') return;

        event.preventDefault();
        this.isToolDropdownOpen = false;
        this.toolSearchTerm = '';
    }

    handleToolOptionClick(event) {
        const toolId = event.currentTarget.dataset.id;
        const selectedTool = this.toolCatalog.find(tool => tool.id === toolId);

        if (!selectedTool) return;

        this.selectedToolId = selectedTool.id;
        this.selectedToolName = selectedTool.name;
        this.toolSearchTerm = '';
        this.isToolDropdownOpen = false;
    }

    handleAddTool() {
        if (!this.selectedToolId) return;

        const selectedTool = this.toolCatalog.find(tool => tool.id === this.selectedToolId);
        if (!selectedTool) return;

        const alreadyExists = this.recommendedTools.some(tool => tool.id === selectedTool.id);

        if (!alreadyExists) {
            this.recommendedTools = [
                ...this.recommendedTools,
                { id: selectedTool.id, name: selectedTool.name }
            ];
        }

        this.selectedToolId = '';
        this.selectedToolName = '';
        this.toolSearchTerm = '';
        this.isToolDropdownOpen = false;
    }

    handleRemoveTool(event) {
        const toolId = event.currentTarget.dataset.id;
        this.recommendedTools = this.recommendedTools.filter(tool => tool.id !== toolId);
    }

    parseTools(value) {
        if (!value || value.trim().toLowerCase() === 'none identified') return [];

        const seen = new Set();

        return value
            .split(/\r?\n|,|;/)
            .map(tool => tool.trim())
            .filter(Boolean)
            .filter(tool => {
                const key = tool.toLowerCase();

                if (seen.has(key)) return false;

                seen.add(key);
                return true;
            })
            .map(tool => ({ id: this.createToolId(tool), name: tool }));
    }

    createToolId(toolName) {
        return toolName
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-|-$/g, '');
    }

    // =========================================================
    // Step 3 - Compatible Part Catalog
    // =========================================================

    async loadCompatibleParts() {
        const manufacturer = this.followUpData?.manufacturer;
        const model = this.followUpData?.model;

        if (!manufacturer || !model) {
            this.catalogParts = [];
            return;
        }

        this.isLoadingParts = true;
        this.partsErrorMessage = '';

        try {
            const parts = await getCompatibleParts({ manufacturer, model });

            const activeExistingPartIds = new Set(
                this.existingParts
                    .filter(part => (part.status || '').toLowerCase() !== 'cancelled')
                    .map(part => part.partCatalogId)
                    .filter(Boolean)
            );

            this.visibleCatalogPartCount = this.catalogPageSize;

            this.catalogParts = (parts || []).map(part => {
                const alreadyRequested = activeExistingPartIds.has(part.id);

                return {
                    ...part,
                    alreadyRequested,
                    selected: !alreadyRequested && this.selectedParts.some(selected => selected.id === part.id),
                    rowClass: alreadyRequested ? 'catalog-row catalog-row-disabled' : 'catalog-row'
                };
            });
        } catch (error) {
            this.partsErrorMessage = this.getErrorMessage(error);
            this.catalogParts = [];
        } finally {
            this.isLoadingParts = false;
        }
    }

    get filteredCatalogParts() {
        const searchTerm = (this.partSearchTerm || '').trim().toLowerCase();
        if (!searchTerm) return this.catalogParts;

        return this.catalogParts.filter(part =>
            [part.name, part.partNumber, part.category, part.compatibleModel]
                .some(value => (value || '').toLowerCase().includes(searchTerm))
        );
    }

    get visibleCatalogParts() {
        return this.filteredCatalogParts.slice(0, this.visibleCatalogPartCount);
    }

    get hasMoreCatalogParts() {
        return this.visibleCatalogPartCount < this.filteredCatalogParts.length;
    }

    get canShowLessCatalogParts() {
        return this.visibleCatalogPartCount > this.catalogPageSize;
    }

    get catalogDisplayCountLabel() {
        return `Showing ${this.visibleCatalogParts.length} of ${this.filteredCatalogParts.length}`;
    }

    get hasCatalogParts() { return this.filteredCatalogParts.length > 0; }
    get hasSelectedParts() { return this.selectedParts.length > 0; }

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
        const part = this.catalogParts.find(item => item.id === partId);

        if (!part || part.alreadyRequested) {
            event.target.checked = false;
            return;
        }

        if (event.target.checked) {
            if (!this.selectedParts.some(item => item.id === partId)) {
                this.selectedParts = [...this.selectedParts, { ...part, quantity: 1 }];
            }
        } else {
            this.selectedParts = this.selectedParts.filter(item => item.id !== partId);
        }

        this.syncCatalogSelectionState();
    }

    handlePartQuantityChange(event) {
        const partId = event.currentTarget.dataset.id;
        const parsedQuantity = Number.parseInt(event.target.value, 10);
        const quantity = Number.isFinite(parsedQuantity) && parsedQuantity > 0 ? parsedQuantity : 1;

        this.selectedParts = this.selectedParts.map(part =>
            part.id === partId ? { ...part, quantity } : part
        );
    }

    handleRemovePart(event) {
        const partId = event.currentTarget.dataset.id;
        this.selectedParts = this.selectedParts.filter(part => part.id !== partId);
        this.syncCatalogSelectionState();
    }

    syncCatalogSelectionState() {
        const selectedIds = new Set(this.selectedParts.map(part => part.id));

        this.catalogParts = this.catalogParts.map(part => ({
            ...part,
            selected: !part.alreadyRequested && selectedIds.has(part.id)
        }));
    }

    // =========================================================
    // Step 4 - Confirmation
    // =========================================================

    get approvalToolCountLabel() {
        const count = this.recommendedTools.length;
        return count === 1 ? '1 tool' : `${count} tools`;
    }

    get approvalPartCountLabel() {
        const count = this.selectedParts.length;
        return count === 1 ? '1 new part selected' : `${count} new parts selected`;
    }

    get approvalDispatchStatus() {
        return this.hasSelectedParts ? 'Parts to Order' : 'Ready to Assign';
    }

    get approvalDispatchClass() {
        return this.hasSelectedParts
            ? 'approval-dispatch-status approval-dispatch-parts'
            : 'approval-dispatch-status approval-dispatch-ready';
    }

    get approvalDispatchDescription() {
        return this.hasSelectedParts
            ? 'The selected follow-up parts will be created as Requested and the Work Order will move to Parts to Order.'
            : 'No additional parts are required before the next visit. The Work Order will move to Ready to Assign.';
    }

    get isApproveDisabled() {
        return this.isApproving || !this.recommendedFixSummary.trim();
    }

    async handleApproveFollowUp() {
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

            const recommendedTools = this.recommendedTools.map(tool => tool.name).join('\n');

            const result = await approveFollowUp({
                workOrderId: this.recordId,
                recommendedFixSummary: this.recommendedFixSummary.trim(),
                recommendedTools,
                selectedPartsJson
            });

            if (!result?.success) {
                throw new Error(result?.message || 'The follow-up plan could not be approved.');
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Follow-Up Plan Approved',
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
                    title: 'Follow-Up Approval Failed',
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

    get isStepOne() { return this.currentStep === 1; }
    get isStepTwo() { return this.currentStep === 2; }
    get isStepThree() { return this.currentStep === 3; }
    get isStepFour() { return this.currentStep === 4; }

    get stepOneClass() {
        return this.currentStep === 1 ? 'progress-step active' : 'progress-step complete';
    }

    get stepTwoClass() {
        if (this.currentStep === 2) return 'progress-step active';
        return this.currentStep > 2 ? 'progress-step complete' : 'progress-step';
    }

    get stepThreeClass() {
        if (this.currentStep === 3) return 'progress-step active';
        return this.currentStep > 3 ? 'progress-step complete' : 'progress-step';
    }

    get stepFourClass() {
        return this.currentStep === 4 ? 'progress-step active' : 'progress-step';
    }

    handleContinue() {
        this.currentStep = 2;
        this.syncRecommendedFixSummaryInput();
    }

    handleBack() {
        const nextStep = Math.max(1, this.currentStep - 1);
        this.currentStep = nextStep;

        if (nextStep === 2) this.syncRecommendedFixSummaryInput();
    }

    handleContinueToParts() {
        if (!this.recommendedFixSummary.trim()) {
            this.planErrorMessage = 'Enter the Recommended Fix Summary for the follow-up visit before continuing.';
            return;
        }

        this.planErrorMessage = '';
        this.currentStep = 3;
    }

    handleContinueToApproval() {
        this.currentStep = 4;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // =========================================================
    // Utilities
    // =========================================================

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;

        return 'The Work Order follow-up could not be loaded.';
    }
}