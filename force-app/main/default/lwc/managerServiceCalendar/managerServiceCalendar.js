import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCalendarData from '@salesforce/apex/ManagerServiceCalendarController.getCalendarData';

const WEEKDAY_LABELS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

export default class ManagerServiceCalendar extends NavigationMixin(LightningElement) {

    displayedYear; displayedMonth;
    calendarData; calendarDays = []; preparedEvents = []; eventsByDate = {};
    selectedDateKey; selectedDateLabel; selectedEvents = []; selectedEventIndex = 0;
    isLoading = true; errorMessage;


    // =========================================================
    // Lifecycle
    // =========================================================

    connectedCallback() {
        const today = new Date();

        this.displayedYear = today.getFullYear();
        this.displayedMonth = today.getMonth() + 1;

        this.loadCalendar();
    }


    // =========================================================
    // Load
    // =========================================================

    async loadCalendar() {
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const data = await getCalendarData({ year: this.displayedYear, month: this.displayedMonth });

            this.calendarData = data;
            this.preparedEvents = (data?.events || []).map(eventRecord => this.prepareEvent(eventRecord));
            this.eventsByDate = this.groupEventsByDate(this.preparedEvents);

            if (this.selectedDateKey && !this.isDateInDisplayedMonth(this.selectedDateKey)) this.clearSelectedDay();

            this.buildCalendarGrid();

            if (this.selectedDateKey) this.updateSelectedDay(this.selectedDateKey);
        } catch (error) {
            this.calendarData = null;
            this.preparedEvents = [];
            this.eventsByDate = {};
            this.calendarDays = [];
            this.clearSelectedDay();
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }


    // =========================================================
    // Calendar Grid
    // =========================================================

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
            const events = this.eventsByDate[dateKey] || [];

            const visibleEvents = events.slice(0, 2).map(eventRecord => ({
                ...eventRecord,
                chipClass: `calendar-event-chip ${this.getOutcomeClass(eventRecord.outcomeKey)}`
            }));

            const classNames = ['calendar-day'];

            if (dateKey === todayKey) classNames.push('calendar-day_today');
            if (dateKey === this.selectedDateKey) classNames.push('calendar-day_selected');
            if (events.length > 0) classNames.push('calendar-day_has-events');

            days.push({
                key: dateKey,
                dateKey,
                dayNumber,
                isBlank: false,
                isToday: dateKey === todayKey,
                isSelected: dateKey === this.selectedDateKey,
                hasEvents: events.length > 0,
                visibleEvents,
                hasMoreEvents: events.length > 2,
                moreCount: Math.max(events.length - 2, 0),
                dayClass: classNames.join(' ')
            });
        }

        this.calendarDays = days;
    }


    groupEventsByDate(events) {
        const grouped = {};

        events.forEach(eventRecord => {
            if (!eventRecord.dateKey) return;
            if (!grouped[eventRecord.dateKey]) grouped[eventRecord.dateKey] = [];

            grouped[eventRecord.dateKey].push(eventRecord);
        });

        Object.keys(grouped).forEach(dateKey => {
            grouped[dateKey].sort((left, right) => {
                const leftTime = left.eventDateTime ? new Date(left.eventDateTime).getTime() : 0;
                const rightTime = right.eventDateTime ? new Date(right.eventDateTime).getTime() : 0;

                return leftTime - rightTime;
            });
        });

        return grouped;
    }


    // =========================================================
    // Event Preparation
    // =========================================================

    prepareEvent(eventRecord) {
        const dateKey = eventRecord.eventDate || null;
        const timeLabel = eventRecord.eventDateTime
            ? new Date(eventRecord.eventDateTime).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
            : null;

        return {
            ...eventRecord,
            dateKey,
            timeLabel,
            calendarLabel: this.getCalendarEventLabel(eventRecord, timeLabel),

            workOrderNumberDisplay: eventRecord.workOrderNumber || 'Work Order',
            accountNameDisplay: eventRecord.accountName || 'Customer unavailable',
            machineLabelDisplay: eventRecord.machineLabel || eventRecord.assetName || 'Machine unavailable',
            serialNumberDisplay: eventRecord.serialNumber ? `S/N ${eventRecord.serialNumber}` : 'Serial number unavailable',
            technicianNameDisplay: eventRecord.technicianName || 'Technician unavailable',
            caseNumberDisplay: eventRecord.caseNumber ? `Case ${eventRecord.caseNumber}` : 'No linked Service Case',
            caseSubjectDisplay: eventRecord.caseSubject || 'No Case subject available.',
            statusDisplay: eventRecord.outcomeLabel || eventRecord.dispatchStatus || 'Service Visit',

            showWorkOrderAction: !eventRecord.isHistoricalEvent && Boolean(eventRecord.workOrderId),
            showMaintenanceAction: Boolean(eventRecord.isHistoricalEvent && eventRecord.maintenanceLogId),

            outcomeClass: `outcome-badge ${this.getOutcomeClass(eventRecord.outcomeKey)}`,
            swingCardClass: `swing-card ${this.getSwingCardClass(eventRecord.outcomeKey)}`,
            priorityClass: `priority-badge ${this.getPriorityClass(eventRecord.priority)}`
        };
    }


    getCalendarEventLabel(eventRecord, timeLabel) {
        switch (eventRecord.outcomeKey) {
            case 'SCHEDULED': return timeLabel || 'Scheduled';
            case 'IN_PROGRESS': return 'In Progress';
            case 'COMPLETED': return 'Completed';
            case 'FOLLOW_UP': return 'Follow-Up';
            case 'TEMPORARY_REPAIR': return 'Temp Repair';
            case 'PAST_DUE': return 'Past Due';
            default: return 'Service Visit';
        }
    }


    // =========================================================
    // Selected Day / Swing Rack
    // =========================================================

    handleDaySelect(event) {
        const dateKey = event.currentTarget.dataset.date;
        if (!dateKey) return;

        this.selectedDateKey = dateKey;
        this.selectedEventIndex = 0;

        this.updateSelectedDay(dateKey);
        this.buildCalendarGrid();
    }


    updateSelectedDay(dateKey) {
        this.selectedDateLabel = this.formatDateLabel(dateKey);
        this.selectedEvents = [...(this.eventsByDate[dateKey] || [])];

        if (this.selectedEventIndex >= this.selectedEvents.length) this.selectedEventIndex = 0;
    }


    handlePreviousSelectedEvent() {
        if (this.selectedEventIndex <= 0) return;
        this.selectedEventIndex--;
    }


    handleNextSelectedEvent() {
        if (this.selectedEventIndex >= this.selectedEvents.length - 1) return;
        this.selectedEventIndex++;
    }


    handleCloseSelectedDay() {
        this.clearSelectedDay();
        this.buildCalendarGrid();
    }


    handlePopupClick(event) {
        event.stopPropagation();
    }


    clearSelectedDay() {
        this.selectedDateKey = null;
        this.selectedDateLabel = null;
        this.selectedEvents = [];
        this.selectedEventIndex = 0;
    }


    // =========================================================
    // Month Navigation
    // =========================================================

    handlePreviousMonth() {
        if (this.displayedMonth === 1) {
            this.displayedMonth = 12;
            this.displayedYear--;
        } else {
            this.displayedMonth--;
        }

        this.clearSelectedDay();
        this.loadCalendar();
    }


    handleNextMonth() {
        if (this.displayedMonth === 12) {
            this.displayedMonth = 1;
            this.displayedYear++;
        } else {
            this.displayedMonth++;
        }

        this.clearSelectedDay();
        this.loadCalendar();
    }


    async handleToday() {
        const today = new Date();

        this.displayedYear = today.getFullYear();
        this.displayedMonth = today.getMonth() + 1;

        this.clearSelectedDay();
        await this.loadCalendar();
    }


    async handleRefresh() {
        await this.loadCalendar();
    }


    // =========================================================
    // Navigation
    // =========================================================

    handleOpenWorkOrder(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'WorkOrder', actionName: 'view' }
        });
    }


    handleOpenMaintenanceLog(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName: 'Maintenance_Log__c', actionName: 'view' }
        });
    }


    // =========================================================
    // Styling
    // =========================================================

    getOutcomeClass(outcomeKey) {
        switch (outcomeKey) {
            case 'SCHEDULED': return 'outcome-scheduled';
            case 'IN_PROGRESS': return 'outcome-progress';
            case 'COMPLETED': return 'outcome-completed';
            case 'FOLLOW_UP': return 'outcome-follow-up';
            case 'TEMPORARY_REPAIR': return 'outcome-temporary';
            case 'PAST_DUE': return 'outcome-past-due';
            default: return 'outcome-service';
        }
    }


    getSwingCardClass(outcomeKey) {
        switch (outcomeKey) {
            case 'SCHEDULED': return 'swing-card_scheduled';
            case 'IN_PROGRESS': return 'swing-card_progress';
            case 'COMPLETED': return 'swing-card_completed';
            case 'FOLLOW_UP': return 'swing-card_follow-up';
            case 'TEMPORARY_REPAIR': return 'swing-card_temporary';
            case 'PAST_DUE': return 'swing-card_past-due';
            default: return 'swing-card_service';
        }
    }


    getPriorityClass(priority) {
        switch ((priority || '').toLowerCase()) {
            case 'critical': return 'priority-critical';
            case 'high': return 'priority-high';
            case 'medium': return 'priority-medium';
            case 'low': return 'priority-low';
            default: return 'priority-default';
        }
    }


    // =========================================================
    // Display Getters
    // =========================================================

    get weekdayLabels() {
        return WEEKDAY_LABELS.map(label => ({ key: label, label }));
    }


    get monthLabel() {
        return new Date(this.displayedYear, this.displayedMonth - 1, 1)
            .toLocaleString('en-US', { month: 'long', year: 'numeric' });
    }


    get isCurrentMonth() {
        const today = new Date();

        return this.displayedYear === today.getFullYear()
            && this.displayedMonth === today.getMonth() + 1;
    }


    get showGoToTodayButton() {
        return !this.isCurrentMonth;
    }


    get hasSelectedDay() {
        return Boolean(this.selectedDateKey);
    }


    get selectedDayHasEvents() {
        return this.selectedEvents.length > 0;
    }


    get selectedDayEventCountLabel() {
        const count = this.selectedEvents.length;
        return `${count} service ${count === 1 ? 'event' : 'events'}`;
    }


    get totalMonthEventsLabel() {
        const count = this.calendarData?.totalEvents || 0;
        return `${count} ${count === 1 ? 'service event' : 'service events'} this month`;
    }


    get hasError() {
        return Boolean(this.errorMessage);
    }


    get currentSelectedEventList() {
        const selectedEvent = this.selectedEvents[this.selectedEventIndex] || null;
        return selectedEvent ? [selectedEvent] : [];
    }


    get hasMultipleSelectedEvents() {
        return this.selectedEvents.length > 1;
    }


    get previousEventDisabled() {
        return this.selectedEventIndex <= 0;
    }


    get nextEventDisabled() {
        return this.selectedEventIndex >= this.selectedEvents.length - 1;
    }


    get selectedEventPositionLabel() {
        if (!this.selectedEvents.length) return '0 of 0';
        return `${this.selectedEventIndex + 1} of ${this.selectedEvents.length}`;
    }


    // =========================================================
    // Date Helpers
    // =========================================================

    formatDateKey(year, month, day) {
        return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
    }


    getTodayKey() {
        const today = new Date();
        return this.formatDateKey(today.getFullYear(), today.getMonth() + 1, today.getDate());
    }


    formatDateLabel(dateKey) {
        if (!dateKey) return '';

        const [year, month, day] = dateKey.split('-').map(Number);
        const dateValue = new Date(year, month - 1, day);

        return dateValue.toLocaleDateString('en-US', {
            weekday: 'long',
            month: 'long',
            day: 'numeric',
            year: 'numeric'
        });
    }


    isDateInDisplayedMonth(dateKey) {
        if (!dateKey) return false;

        const [year, month] = dateKey.split('-').map(Number);
        return year === this.displayedYear && month === this.displayedMonth;
    }


    // =========================================================
    // Errors
    // =========================================================

    reduceError(error) {
        if (!error) return 'An unexpected error occurred while loading the service calendar.';
        if (Array.isArray(error.body)) return error.body.map(item => item.message).join(', ');
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;

        return 'An unexpected error occurred while loading the service calendar.';
    }
}