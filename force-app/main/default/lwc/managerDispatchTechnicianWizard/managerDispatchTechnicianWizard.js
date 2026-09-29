import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDispatchContext from '@salesforce/apex/ManagerDispatchTechnicianController.getDispatchContext';
import getTechnicianSchedule from '@salesforce/apex/ManagerDispatchTechnicianController.getTechnicianSchedule';
import dispatchTechnician from '@salesforce/apex/ManagerDispatchTechnicianController.dispatchTechnician';

const WEEKDAY_LABELS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const SCHEDULE_BUFFER_MINUTES = 30;

export default class ManagerDispatchTechnicianWizard extends LightningElement {
    @api recordId;

    context;
    parts = [];
    technicians = [];
    saveResult;

    currentStep = 1;

    selectedTechnicianId = '';
    scheduledDate = '';
    scheduledTime = '';
    readyConfirmed = false;

    displayedYear;
    displayedMonth;

    technicianSchedule;
    scheduleVisits = [];
    conflictVisits = [];
    calendarDays = [];

    isLoading = true;
    isSaving = false;
    isScheduleLoading = false;
    showSuccessConfirmation = false;

    errorMessage = '';
    saveErrorMessage = '';
    scheduleErrorMessage = '';

    // =========================================================
    // INITIAL LOAD
    // =========================================================

    async connectedCallback() {
        const today = new Date();
        this.displayedYear = today.getFullYear();
        this.displayedMonth = today.getMonth() + 1;
        await this.loadDispatchContext();
    }

    async loadDispatchContext() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            this.context = await getDispatchContext({ workOrderId: this.recordId });

            if (!this.context?.eligible) {
                this.errorMessage = this.context?.ineligibleReason || 'This Work Order is not available for technician dispatch.';
                return;
            }

            this.parts = (this.context?.parts || []).map((part, index) => ({ ...part, rowNumber: index + 1 }));
            this.technicians = this.context?.technicians || [];
            this.selectedTechnicianId = this.context?.suggestedTechnicianId || '';

            if (this.context?.scheduledVisit) {
                const visit = new Date(this.context.scheduledVisit);

                if (!Number.isNaN(visit.getTime())) {
                    this.scheduledDate = `${visit.getFullYear()}-${String(visit.getMonth() + 1).padStart(2, '0')}-${String(visit.getDate()).padStart(2, '0')}`;
                    this.scheduledTime = `${String(visit.getHours()).padStart(2, '0')}:${String(visit.getMinutes()).padStart(2, '0')}`;
                    this.displayedYear = visit.getFullYear();
                    this.displayedMonth = visit.getMonth() + 1;
                }
            }

            if (this.selectedTechnicianId) await this.loadTechnicianSchedule();
            else this.buildCalendarGrid();
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================
    // HEADER
    // =========================================================

    get workOrderNumber() { return this.context?.workOrderNumber ? `WO ${this.context.workOrderNumber}` : 'Work Order'; }
    get assetName() { return this.context?.assetName || 'Machine not available'; }
    get accountName() { return this.context?.accountName || 'Customer not available'; }
    get dispatchStatus() { return this.context?.dispatchStatus || 'Not Set'; }
    get priority() { return this.context?.priority || 'Not Set'; }
    get problemSummary() { return this.context?.problemSummary || 'No problem summary is available.'; }
    get recommendedFixSummary() { return this.context?.recommendedFixSummary || 'No approved repair summary is available.'; }

    // =========================================================
    // STEP STATE
    // =========================================================

    get isStepOne() { return this.currentStep === 1; }
    get isStepTwo() { return this.currentStep === 2; }
    get stepOneClass() { return this.currentStep === 1 ? 'progress-step active' : 'progress-step complete'; }
    get stepTwoClass() { return this.currentStep === 2 ? 'progress-step active' : 'progress-step'; }

    // =========================================================
    // PARTS
    // =========================================================

    get hasParts() { return this.parts.length > 0; }

    get partCountLabel() {
        const count = this.parts.length;
        return count === 1 ? '1 required part' : `${count} required parts`;
    }

    get displayParts() {
        return this.parts.map(part => ({ ...part, statusClass: this.getPartStatusClass(part.status) }));
    }

    get blockingParts() {
        return this.parts.filter(part => ['Requested', 'Ordered', 'Shipped'].includes(part.status));
    }

    get hasBlockingParts() { return this.blockingParts.length > 0; }

    get blockingPartMessage() {
        const count = this.blockingParts.length;
        if (count === 1) return '1 required part is still outstanding. Receive the part before dispatching a technician.';
        return `${count} required parts are still outstanding. Receive those parts before dispatching a technician.`;
    }

    getPartStatusClass(status) {
        if (status === 'Received' || status === 'Installed') return 'part-status part-status-ready';
        if (status === 'Cancelled') return 'part-status part-status-cancelled';
        return 'part-status part-status-outstanding';
    }

    // =========================================================
    // TECHNICIAN / SCHEDULE
    // =========================================================

    get technicianOptions() {
        return this.technicians.map(technician => ({ label: technician.name, value: technician.id }));
    }

    get hasTechnicians() { return this.technicians.length > 0; }
    get hasSelectedTechnician() { return Boolean(this.selectedTechnicianId); }

    get selectedTechnicianName() {
        const technician = this.technicians.find(item => item.id === this.selectedTechnicianId);
        return technician?.name || 'No technician selected';
    }

    get scheduledVisit() {
        if (!this.scheduledDate || !this.scheduledTime) return '';

        const visit = new Date(`${this.scheduledDate}T${this.scheduledTime}`);
        return Number.isNaN(visit.getTime()) ? '' : visit.toISOString();
    }

    get scheduledVisitInPast() {
        if (!this.scheduledVisit) return false;
        return new Date(this.scheduledVisit).getTime() < Date.now();
    }

    get todayDate() { return this.getTodayKey(); }

    get scheduledVisitDisplay() {
        if (!this.scheduledVisit) return 'No visit scheduled';

        const value = new Date(this.scheduledVisit);
        if (Number.isNaN(value.getTime())) return this.scheduledVisit;

        return new Intl.DateTimeFormat('en-CA', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(value);
    }

    // =========================================================
    // TECHNICIAN CALENDAR
    // =========================================================

    async loadTechnicianSchedule() {
        if (!this.selectedTechnicianId) {
            this.technicianSchedule = null;
            this.scheduleVisits = [];
            this.conflictVisits = [];
            this.scheduleErrorMessage = '';
            this.buildCalendarGrid();
            return;
        }

        this.isScheduleLoading = true;
        this.scheduleErrorMessage = '';

        try {
            const previous = this.getAdjacentMonth(-1);
            const current = { year: this.displayedYear, month: this.displayedMonth };
            const next = this.getAdjacentMonth(1);

            const [previousData, currentData, nextData] = await Promise.all([
                this.loadScheduleMonth(previous.year, previous.month),
                this.loadScheduleMonth(current.year, current.month),
                this.loadScheduleMonth(next.year, next.month)
            ]);

            this.technicianSchedule = currentData;

            this.scheduleVisits = [
                ...(previousData?.visits || []),
                ...(currentData?.visits || []),
                ...(nextData?.visits || [])
            ].map(visit => this.prepareScheduleVisit(visit));

            this.buildCalendarGrid();
            this.evaluateScheduleConflict();
        } catch (error) {
            this.technicianSchedule = null;
            this.scheduleVisits = [];
            this.conflictVisits = [];
            this.calendarDays = [];
            this.scheduleErrorMessage = this.getErrorMessage(error);
        } finally {
            this.isScheduleLoading = false;
        }
    }

    async loadScheduleMonth(year, month) {
        return getTechnicianSchedule({
            technicianId: this.selectedTechnicianId,
            year,
            month,
            excludedWorkOrderId: this.recordId
        });
    }

    prepareScheduleVisit(visit) {
        const isCompleted = visit?.visitType === 'Completed' || visit?.dispatchStatus === 'Completed';
        const dateValue = visit?.scheduledVisit ? new Date(visit.scheduledVisit) : null;
        const validDate = dateValue && !Number.isNaN(dateValue.getTime());
        const dateKey = isCompleted && visit?.visitDate
            ? visit.visitDate
            : validDate
                ? this.formatDateKey(dateValue.getFullYear(), dateValue.getMonth() + 1, dateValue.getDate())
                : '';

        return {
            ...visit,
            dateKey,
            visitKey: visit.maintenanceLogId || visit.workOrderId || `${dateKey}-${visit.dispatchStatus || 'visit'}`,
            timeLabel: isCompleted
                ? 'Completed'
                : validDate
                    ? dateValue.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
                    : '',
            visitTime: visit?.blocksScheduling === false || isCompleted ? null : validDate ? dateValue.getTime() : null,
            displayAccount: visit.accountName || 'Customer unavailable',
            displayMachine: visit.machineLabel || visit.assetName || 'Machine unavailable'
        };
    }

    buildCalendarGrid() {
        const firstDay = new Date(this.displayedYear, this.displayedMonth - 1, 1);
        const daysInMonth = new Date(this.displayedYear, this.displayedMonth, 0).getDate();
        const leadingBlankCount = firstDay.getDay();
        const totalCells = Math.ceil((leadingBlankCount + daysInMonth) / 7) * 7;
        const days = [];
        const todayKey = this.getTodayKey();

        for (let cellIndex = 0; cellIndex < totalCells; cellIndex++) {
            const dayNumber = cellIndex - leadingBlankCount + 1;

            if (dayNumber < 1 || dayNumber > daysInMonth) {
                days.push({ key: `blank-${cellIndex}`, isBlank: true });
                continue;
            }

            const dateKey = this.formatDateKey(this.displayedYear, this.displayedMonth, dayNumber);
            const isPast = dateKey < todayKey;

            const visits = this.scheduleVisits
                .filter(visit => visit.dateKey === dateKey)
                .sort((left, right) => {
                    if (left.dispatchStatus === 'Completed' && right.dispatchStatus !== 'Completed') return -1;
                    if (right.dispatchStatus === 'Completed' && left.dispatchStatus !== 'Completed') return 1;
                    return (left.visitTime || 0) - (right.visitTime || 0);
                });

            const visibleVisits = visits.slice(0, 2).map(visit => ({
                ...visit,
                chipClass: visit.dispatchStatus === 'Completed'
                    ? 'availability-event availability-event-completed'
                    : visit.dispatchStatus === 'In Progress'
                        ? 'availability-event availability-event-progress'
                        : 'availability-event availability-event-scheduled'
            }));

            const classNames = ['availability-day'];

            if (dateKey === todayKey) classNames.push('availability-day-today');
            if (isPast) classNames.push('availability-day-past');
            if (!isPast && dateKey === this.scheduledDate) classNames.push(visits.length > 0 ? 'availability-day-selected-busy' : 'availability-day-selected');
            if (visits.length > 0) classNames.push('availability-day-has-visits');

            days.push({
                key: dateKey,
                dateKey,
                dayNumber,
                isBlank: false,
                isToday: dateKey === todayKey,
                isPast,
                isDisabled: isPast,
                hasVisits: visits.length > 0,
                visibleVisits,
                hasMoreVisits: visits.length > 2,
                moreVisitCount: Math.max(visits.length - 2, 0),
                dayClass: classNames.join(' ')
            });
        }

        this.calendarDays = days;
    }

    get weekdayLabels() {
        return WEEKDAY_LABELS.map(label => ({ key: label, label }));
    }

    get monthLabel() {
        return new Date(this.displayedYear, this.displayedMonth - 1, 1).toLocaleString('en-US', {
            month: 'long',
            year: 'numeric'
        });
    }

    get displayedMonthVisitCount() {
        return this.scheduleVisits.filter(visit => {
            if (!visit.dateKey) return false;

            const [year, month] = visit.dateKey.split('-').map(Number);
            return year === this.displayedYear && month === this.displayedMonth;
        }).length;
    }

    get displayedMonthVisitLabel() {
        const count = this.displayedMonthVisitCount;
        return count === 1 ? '1 visit' : `${count} visits`;
    }

    get showScheduleCalendar() {
        return this.hasSelectedTechnician && !this.isScheduleLoading && !this.scheduleErrorMessage;
    }

    get hasScheduleError() { return Boolean(this.scheduleErrorMessage); }

    get selectedDateVisits() {
        if (!this.scheduledDate) return [];

        return this.scheduleVisits
            .filter(visit => visit.dateKey === this.scheduledDate)
            .sort((left, right) => (left.visitTime || 0) - (right.visitTime || 0));
    }

    get selectedDateHasVisits() { return this.selectedDateVisits.length > 0; }

    get selectedDateVisitCountLabel() {
        const count = this.selectedDateVisits.length;
        return count === 1 ? '1 existing visit on this day' : `${count} existing visits on this day`;
    }

    get selectedDateDisplay() {
        if (!this.scheduledDate) return '';

        const [year, month, day] = this.scheduledDate.split('-').map(Number);

        return new Date(year, month - 1, day).toLocaleDateString('en-US', {
            weekday: 'long',
            month: 'long',
            day: 'numeric',
            year: 'numeric'
        });
    }

    // =========================================================
    // SCHEDULE CONFLICT
    // =========================================================

    evaluateScheduleConflict() {
        this.conflictVisits = [];

        if (!this.selectedTechnicianId || !this.scheduledVisit) return;

        const proposedTime = new Date(this.scheduledVisit).getTime();
        const bufferMilliseconds = SCHEDULE_BUFFER_MINUTES * 60 * 1000;

        this.conflictVisits = this.scheduleVisits.filter(visit => {
            if (visit.blocksScheduling === false || !visit.visitTime) return false;
            return Math.abs(proposedTime - visit.visitTime) <= bufferMilliseconds;
        });
    }

    get hasScheduleConflict() { return this.conflictVisits.length > 0; }

    get scheduleConflictMessage() {
        if (!this.hasScheduleConflict) return '';

        const conflict = this.conflictVisits[0];

        return (
            `${this.selectedTechnicianName} already has ` +
            `${conflict.workOrderNumber || 'another visit'} ` +
            `scheduled for ${conflict.timeLabel}. ` +
            `Choose a time more than 30 minutes before or after that visit.`
        );
    }

    // =========================================================
    // CALENDAR NAVIGATION
    // =========================================================

    async handlePreviousMonth() {
        if (this.displayedMonth === 1) {
            this.displayedMonth = 12;
            this.displayedYear--;
        } else {
            this.displayedMonth--;
        }

        await this.loadTechnicianSchedule();
    }

    async handleNextMonth() {
        if (this.displayedMonth === 12) {
            this.displayedMonth = 1;
            this.displayedYear++;
        } else {
            this.displayedMonth++;
        }

        await this.loadTechnicianSchedule();
    }

    async handleToday() {
        const today = new Date();
        this.displayedYear = today.getFullYear();
        this.displayedMonth = today.getMonth() + 1;
        await this.loadTechnicianSchedule();
    }

    async handleCalendarDaySelect(event) {
        const dateKey = event.currentTarget.dataset.date;
        if (!dateKey || dateKey < this.getTodayKey()) return;

        this.scheduledDate = dateKey;
        this.saveErrorMessage = '';
        this.evaluateScheduleConflict();
        this.buildCalendarGrid();
    }

    // =========================================================
    // FIELD CHANGES
    // =========================================================

    async handleTechnicianChange(event) {
        this.selectedTechnicianId = event.detail.value;
        this.saveErrorMessage = '';
        this.scheduleErrorMessage = '';
        this.conflictVisits = [];

        if (!this.selectedTechnicianId) {
            this.technicianSchedule = null;
            this.scheduleVisits = [];
            this.calendarDays = [];
            return;
        }

        if (this.scheduledDate) {
            const [year, month] = this.scheduledDate.split('-').map(Number);
            this.displayedYear = year;
            this.displayedMonth = month;
        } else {
            const today = new Date();
            this.displayedYear = today.getFullYear();
            this.displayedMonth = today.getMonth() + 1;
        }

        await this.loadTechnicianSchedule();
    }

    async handleScheduledDateChange(event) {
        const selectedDate = event.target.value;
        this.saveErrorMessage = '';

        if (selectedDate && selectedDate < this.getTodayKey()) {
            this.scheduledDate = '';
            event.target.value = '';
            this.evaluateScheduleConflict();
            this.buildCalendarGrid();
            return;
        }

        this.scheduledDate = selectedDate;

        if (this.selectedTechnicianId && this.scheduledDate) {
            const [year, month] = this.scheduledDate.split('-').map(Number);
            const monthChanged = year !== this.displayedYear || month !== this.displayedMonth;

            this.displayedYear = year;
            this.displayedMonth = month;

            if (monthChanged) {
                await this.loadTechnicianSchedule();
            } else {
                this.evaluateScheduleConflict();
                this.buildCalendarGrid();
            }
        } else {
            this.evaluateScheduleConflict();
            this.buildCalendarGrid();
        }
    }

    handleScheduledTimeChange(event) {
        this.scheduledTime = event.target.value;
        this.saveErrorMessage = '';
        this.evaluateScheduleConflict();
    }

    handleReadyChange(event) {
        this.readyConfirmed = event.target.checked;
        this.saveErrorMessage = '';
    }

    // =========================================================
    // VALIDATION
    // =========================================================

    get isContinueDisabled() {
        return (
            this.isSaving ||
            this.isScheduleLoading ||
            !this.hasTechnicians ||
            !this.selectedTechnicianId ||
            !this.scheduledDate ||
            !this.scheduledTime ||
            this.scheduledVisitInPast ||
            this.hasScheduleConflict ||
            this.hasScheduleError ||
            !this.readyConfirmed ||
            this.hasBlockingParts
        );
    }

    // =========================================================
    // NAVIGATION
    // =========================================================

    handleContinue() {
        if (this.isContinueDisabled) return;
        this.saveErrorMessage = '';
        this.currentStep = 2;
    }

    handleBack() {
        if (this.isSaving) return;

        this.saveErrorMessage = '';

        if (this.currentStep === 2) this.currentStep = 1;
    }

    handleCancel() {
        if (this.isSaving || this.showSuccessConfirmation) return;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    // =========================================================
    // STEP 2
    // =========================================================

    get isDispatchDisabled() {
        return (
            this.isSaving ||
            !this.recordId ||
            !this.selectedTechnicianId ||
            !this.scheduledDate ||
            !this.scheduledTime ||
            this.scheduledVisitInPast ||
            this.hasScheduleConflict ||
            !this.readyConfirmed ||
            this.hasBlockingParts
        );
    }

    // =========================================================
    // SAVE
    // =========================================================

    async handleDispatch() {
        if (this.isDispatchDisabled) return;

        this.isSaving = true;
        this.saveErrorMessage = '';

        try {
            this.saveResult = await dispatchTechnician({
                workOrderId: this.recordId,
                technicianId: this.selectedTechnicianId,
                scheduledVisit: this.scheduledVisit
            });

            this.showSuccessConfirmation = true;
        } catch (error) {
            this.saveErrorMessage = this.getErrorMessage(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to Dispatch Technician',
                    message: this.saveErrorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    // =========================================================
    // SUCCESS
    // =========================================================

    get successHeading() { return 'Technician Dispatched'; }

    get successMessage() {
        const technicianName = this.saveResult?.technicianName || this.selectedTechnicianName;
        return `${this.workOrderNumber} has been assigned to ${technicianName} for ${this.scheduledVisitDisplay}.`;
    }

    get successWorkOrderStatus() { return this.saveResult?.workOrderStatus || 'Assigned'; }
    get successCaseStatus() { return this.saveResult?.caseStatus || 'Scheduled'; }

    get successNextStepMessage() {
        const technicianName = this.saveResult?.technicianName || this.selectedTechnicianName;

        return (
            `The Work Order is now available in ${technicianName}'s ` +
            `assigned service work. ${technicianName} will visit ` +
            `${this.accountName} on ${this.scheduledVisitDisplay} ` +
            `to perform the approved repair.`
        );
    }

    handleSuccessClose() {
        const result = this.saveResult || {};

        this.dispatchEvent(
            new CustomEvent('complete', {
                detail: {
                    workOrderId: result.workOrderId || this.recordId,
                    workOrderNumber: result.workOrderNumber,
                    workOrderStatus: result.workOrderStatus,
                    caseStatus: result.caseStatus,
                    assetStatus: result.assetStatus,
                    technicianId: result.technicianId || this.selectedTechnicianId,
                    technicianName: result.technicianName || this.selectedTechnicianName,
                    scheduledVisit: result.scheduledVisit || this.scheduledVisit
                }
            })
        );
    }

    // =========================================================
    // DATE HELPERS
    // =========================================================

    getAdjacentMonth(offset) {
        const dateValue = new Date(this.displayedYear, this.displayedMonth - 1 + offset, 1);
        return { year: dateValue.getFullYear(), month: dateValue.getMonth() + 1 };
    }

    formatDateKey(year, month, day) {
        return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    }

    getTodayKey() {
        const today = new Date();
        return this.formatDateKey(today.getFullYear(), today.getMonth() + 1, today.getDate());
    }

    // =========================================================
    // ERROR HANDLING
    // =========================================================

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred.';
    }
}