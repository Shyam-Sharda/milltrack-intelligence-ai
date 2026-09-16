public with sharing class TechnicianHomeController {

    private static final String STATUS_IN_PROGRESS = 'In Progress';
    private static final Integer UPCOMING_VISIT_LIMIT = 3;
    private static final Integer SCHEDULED_QUERY_LIMIT = 4;
    private static final Integer SIMILAR_REPAIR_LIMIT = 2;
    private static final Integer UPCOMING_SIMILAR_REPAIR_LIMIT = 2;

    private static final Set<String> EXCLUDED_SCHEDULED_STATUSES = new Set<String>{
        'In Progress', 'Completed', 'Waiting on Parts', 'Parts to Order', 'Temporary Fix'
    };

    /*
     * Technician AI has access to the larger knowledge library.
     * These are the two curated quick-reference PDFs shown on Technician Home.
     */
    private static final List<String> FEATURED_MANUAL_TITLES = new List<String>{
        'Ceramill Motion User Manual',
        'DWX-52D User Manual'
    };


    // =========================================================
    // Home Data
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static TechnicianHomeData getHomeData() {
        TechnicianHomeData result = new TechnicianHomeData();

        result.technicianId = UserInfo.getUserId();
        result.upcomingVisits = new List<VisitDTO>();
        result.serviceManuals = new List<ManualDTO>();
        result.similarRepairs = new List<SimilarRepairDTO>();

        populateTechnician(result);

        List<WorkOrder> inProgressWorkOrders = getInProgressWorkOrders();
        List<WorkOrder> scheduledWorkOrders = getScheduledWorkOrders();

        WorkOrder currentWorkOrder;

        if (!inProgressWorkOrders.isEmpty()) {
            currentWorkOrder = inProgressWorkOrders[0];
        } else if (!scheduledWorkOrders.isEmpty()) {
            currentWorkOrder = scheduledWorkOrders.remove(0);
        }

        if (currentWorkOrder != null) {
            result.currentVisit = buildVisit(currentWorkOrder);
            result.similarRepairs = getSimilarRepairs(
                currentWorkOrder.Id,
                SIMILAR_REPAIR_LIMIT
            );
        }

        Integer upcomingCount = Math.min(
            UPCOMING_VISIT_LIMIT,
            scheduledWorkOrders.size()
        );

        for (Integer i = 0; i < upcomingCount; i++) {
            WorkOrder scheduledWorkOrder = scheduledWorkOrders[i];
            VisitDTO visit = buildVisit(scheduledWorkOrder);

            List<SimilarRepairDTO> visitRepairs = getSimilarRepairs(
                scheduledWorkOrder.Id,
                UPCOMING_SIMILAR_REPAIR_LIMIT
            );

            visit.similarRepairs = visitRepairs;
            if (!visitRepairs.isEmpty()) visit.similarRepair = visitRepairs[0];

            result.upcomingVisits.add(visit);
        }

        result.serviceManuals = getServiceManuals();

        return result;
    }


    // =========================================================
    // Technician
    // =========================================================

    private static void populateTechnician(TechnicianHomeData result) {
        List<User> users = [
            SELECT Id, FirstName, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];

        if (users.isEmpty()) return;

        result.technicianName = users[0].Name;
        result.technicianFirstName =
            String.isBlank(users[0].FirstName)
            ? users[0].Name
            : users[0].FirstName;
    }


    // =========================================================
    // Current In-Progress Visit
    // =========================================================

    private static List<WorkOrder> getInProgressWorkOrders() {
        Id technicianId = UserInfo.getUserId();

        return [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Priority,
                Status,
                Dispatch_Status__c,
                Scheduled_Visit__c,
                Work_Started_Date_Time__c,
                Problem_Summary__c,
                Recommended_Fix_Summary__c,
                Recommended_Tools__c,

                AccountId,
                Account.Name,
                Account.ShippingStreet,
                Account.ShippingCity,
                Account.ShippingState,
                Account.ShippingPostalCode,
                Account.ShippingCountry,
                Account.BillingStreet,
                Account.BillingCity,
                Account.BillingState,
                Account.BillingPostalCode,
                Account.BillingCountry,

                ContactId,
                Contact.Name,
                Contact.Phone,
                Contact.Email,

                AssetId,
                Asset.Name,
                Asset.Manufacturer__c,
                Asset.Model__c,
                Asset.Serial_Number__c,
                Asset.Machine_Status__c,

                CaseId,
                Case.CaseNumber,
                Case.Subject,
                Case.ContactId,
                Case.Contact.Name,
                Case.Contact.Phone,
                Case.Contact.Email,

                Street,
                City,
                State,
                PostalCode,
                Country
            FROM WorkOrder
            WHERE Suggested_Technician__c = :technicianId
                AND Dispatch_Status__c = :STATUS_IN_PROGRESS
            WITH USER_MODE
            ORDER BY
                Work_Started_Date_Time__c DESC NULLS LAST,
                Scheduled_Visit__c ASC NULLS LAST
            LIMIT 1
        ];
    }


    // =========================================================
    // Upcoming Scheduled Visits
    // =========================================================

    private static List<WorkOrder> getScheduledWorkOrders() {
        Id technicianId = UserInfo.getUserId();

        return [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                Priority,
                Status,
                Dispatch_Status__c,
                Scheduled_Visit__c,
                Work_Started_Date_Time__c,
                Problem_Summary__c,
                Recommended_Fix_Summary__c,
                Recommended_Tools__c,

                AccountId,
                Account.Name,
                Account.ShippingStreet,
                Account.ShippingCity,
                Account.ShippingState,
                Account.ShippingPostalCode,
                Account.ShippingCountry,
                Account.BillingStreet,
                Account.BillingCity,
                Account.BillingState,
                Account.BillingPostalCode,
                Account.BillingCountry,

                ContactId,
                Contact.Name,
                Contact.Phone,
                Contact.Email,

                AssetId,
                Asset.Name,
                Asset.Manufacturer__c,
                Asset.Model__c,
                Asset.Serial_Number__c,
                Asset.Machine_Status__c,

                CaseId,
                Case.CaseNumber,
                Case.Subject,
                Case.ContactId,
                Case.Contact.Name,
                Case.Contact.Phone,
                Case.Contact.Email,

                Street,
                City,
                State,
                PostalCode,
                Country
            FROM WorkOrder
            WHERE Suggested_Technician__c = :technicianId
                AND Scheduled_Visit__c >= TODAY
                AND (
                    Dispatch_Status__c = NULL
                    OR Dispatch_Status__c NOT IN :EXCLUDED_SCHEDULED_STATUSES
                )
            WITH USER_MODE
            ORDER BY Scheduled_Visit__c ASC
            LIMIT :SCHEDULED_QUERY_LIMIT
        ];
    }


    // =========================================================
    // Visit DTO
    // =========================================================

    private static VisitDTO buildVisit(WorkOrder workOrderRecord) {
        VisitDTO visit = new VisitDTO();
        visit.similarRepairs = new List<SimilarRepairDTO>();

        visit.workOrderId = workOrderRecord.Id;
        visit.workOrderNumber = workOrderRecord.WorkOrderNumber;
        visit.subject = workOrderRecord.Subject;
        visit.priority = workOrderRecord.Priority;
        visit.status = workOrderRecord.Status;
        visit.dispatchStatus = workOrderRecord.Dispatch_Status__c;
        visit.scheduledVisit = workOrderRecord.Scheduled_Visit__c;
        visit.workStartedDateTime = workOrderRecord.Work_Started_Date_Time__c;
        visit.isInProgress =
            workOrderRecord.Dispatch_Status__c == STATUS_IN_PROGRESS;

        visit.problemSummary =
            safeText(workOrderRecord.Problem_Summary__c);

        visit.recommendedFixSummary =
            safeText(workOrderRecord.Recommended_Fix_Summary__c);

        visit.recommendedTools =
            safeText(workOrderRecord.Recommended_Tools__c);

        visit.accountId = workOrderRecord.AccountId;
        visit.accountName =
            workOrderRecord.Account == null
            ? null
            : workOrderRecord.Account.Name;

        visit.assetId = workOrderRecord.AssetId;

        if (workOrderRecord.Asset != null) {
            visit.assetName = workOrderRecord.Asset.Name;
            visit.manufacturer = workOrderRecord.Asset.Manufacturer__c;
            visit.model = workOrderRecord.Asset.Model__c;
            visit.serialNumber = workOrderRecord.Asset.Serial_Number__c;
            visit.machineStatus = workOrderRecord.Asset.Machine_Status__c;

            visit.machineLabel = buildMachineLabel(
                workOrderRecord.Asset.Manufacturer__c,
                workOrderRecord.Asset.Model__c
            );
        }

        visit.caseId = workOrderRecord.CaseId;

        if (workOrderRecord.Case != null) {
            visit.caseNumber = workOrderRecord.Case.CaseNumber;
            visit.caseSubject = workOrderRecord.Case.Subject;
        }

        populateContact(visit, workOrderRecord);
        populateAddress(visit, workOrderRecord);

        return visit;
    }


    // =========================================================
    // Contact
    // =========================================================

    private static void populateContact(
        VisitDTO visit,
        WorkOrder workOrderRecord
    ) {
        if (workOrderRecord.Contact != null) {
            visit.contactId = workOrderRecord.ContactId;
            visit.contactName = workOrderRecord.Contact.Name;
            visit.contactPhone = workOrderRecord.Contact.Phone;
            visit.contactEmail = workOrderRecord.Contact.Email;
            return;
        }

        if (
            workOrderRecord.Case != null
            && workOrderRecord.Case.Contact != null
        ) {
            visit.contactId = workOrderRecord.Case.ContactId;
            visit.contactName = workOrderRecord.Case.Contact.Name;
            visit.contactPhone = workOrderRecord.Case.Contact.Phone;
            visit.contactEmail = workOrderRecord.Case.Contact.Email;
        }
    }


    // =========================================================
    // Address
    //
    // Priority:
    // 1. Work Order service address
    // 2. Account Shipping Address
    // 3. Account Billing Address
    // =========================================================

    private static void populateAddress(
        VisitDTO visit,
        WorkOrder workOrderRecord
    ) {
        String street = workOrderRecord.Street;
        String city = workOrderRecord.City;
        String state = workOrderRecord.State;
        String postalCode = workOrderRecord.PostalCode;
        String country = workOrderRecord.Country;

        if (
            !hasAddress(street, city, state, postalCode, country)
            && workOrderRecord.Account != null
        ) {
            street = workOrderRecord.Account.ShippingStreet;
            city = workOrderRecord.Account.ShippingCity;
            state = workOrderRecord.Account.ShippingState;
            postalCode = workOrderRecord.Account.ShippingPostalCode;
            country = workOrderRecord.Account.ShippingCountry;
        }

        if (
            !hasAddress(street, city, state, postalCode, country)
            && workOrderRecord.Account != null
        ) {
            street = workOrderRecord.Account.BillingStreet;
            city = workOrderRecord.Account.BillingCity;
            state = workOrderRecord.Account.BillingState;
            postalCode = workOrderRecord.Account.BillingPostalCode;
            country = workOrderRecord.Account.BillingCountry;
        }

        visit.street = street;
        visit.city = city;
        visit.state = state;
        visit.postalCode = postalCode;
        visit.country = country;
        visit.fullAddress = buildFullAddress(
            street,
            city,
            state,
            postalCode,
            country
        );
    }

    private static Boolean hasAddress(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        return !String.isBlank(street)
            || !String.isBlank(city)
            || !String.isBlank(state)
            || !String.isBlank(postalCode)
            || !String.isBlank(country);
    }

    private static String buildFullAddress(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        List<String> addressParts = new List<String>();

        if (!String.isBlank(street)) {
            addressParts.add(street.trim());
        }

        String cityState = '';

        if (!String.isBlank(city)) {
            cityState = city.trim();
        }

        if (!String.isBlank(state)) {
            cityState +=
                String.isBlank(cityState)
                ? state.trim()
                : ', ' + state.trim();
        }

        if (!String.isBlank(postalCode)) {
            cityState +=
                String.isBlank(cityState)
                ? postalCode.trim()
                : ' ' + postalCode.trim();
        }

        if (!String.isBlank(cityState)) {
            addressParts.add(cityState);
        }

        if (!String.isBlank(country)) {
            addressParts.add(country.trim());
        }

        return String.join(addressParts, ', ');
    }


    // =========================================================
    // Similar Repairs
    // =========================================================

    private static List<SimilarRepairDTO> getSimilarRepairs(
        Id workOrderId,
        Integer maxResults
    ) {
        List<SimilarRepairDTO> repairs = new List<SimilarRepairDTO>();

        if (workOrderId == null) return repairs;

        List<GetRelevantHistoricalRepairs.HistoricalRepairUi> historicalRepairs =
            GetRelevantHistoricalRepairs.getHistoricalRepairsForLwc(
                workOrderId,
                maxResults
            );

        if (historicalRepairs.isEmpty()) return repairs;

        Set<Id> maintenanceLogIds = new Set<Id>();

        for (
            GetRelevantHistoricalRepairs.HistoricalRepairUi historicalRepair
            : historicalRepairs
        ) {
            if (historicalRepair.maintenanceLogId != null) {
                maintenanceLogIds.add(historicalRepair.maintenanceLogId);
            }
        }

        Map<Id, Maintenance_Log__c> maintenanceLogsById =
            new Map<Id, Maintenance_Log__c>();

        if (!maintenanceLogIds.isEmpty()) {
            maintenanceLogsById = new Map<Id, Maintenance_Log__c>([
                SELECT
                    Id,
                    Name,
                    Problem_Summary__c,
                    Summary__c
                FROM Maintenance_Log__c
                WHERE Id IN :maintenanceLogIds
                WITH USER_MODE
            ]);
        }

        for (
            GetRelevantHistoricalRepairs.HistoricalRepairUi historicalRepair
            : historicalRepairs
        ) {
            SimilarRepairDTO repair = new SimilarRepairDTO();

            repair.maintenanceLogId = historicalRepair.maintenanceLogId;
            repair.workOrderId = historicalRepair.workOrderId;

            /*
             * Keep the existing fields for Upcoming Visits until
             * that section receives its own visual update.
             */
            repair.subject = historicalRepair.subject;
            repair.caseSubject = historicalRepair.caseSubject;
            repair.matchedKeywords = historicalRepair.matchedKeywords;
            repair.recommendedFixSummary =
                historicalRepair.recommendedFixSummary;

            Maintenance_Log__c maintenanceLog =
                maintenanceLogsById.get(historicalRepair.maintenanceLogId);

            if (maintenanceLog != null) {
                repair.maintenanceLogName = maintenanceLog.Name;
                repair.problemSummary =
                    safeText(maintenanceLog.Problem_Summary__c);
                repair.repairSummary =
                    safeText(maintenanceLog.Summary__c);
            }

            repairs.add(repair);
        }

        return repairs;
    }


    // =========================================================
    // Quick Service Manuals
    //
    // Follow the same access path the technician uses:
    //
    // Service_Manual__c
    //      ↓
    // ContentDocumentLink
    //      ↓
    // ContentDocument
    // =========================================================

    private static List<ManualDTO> getServiceManuals() {
        List<ManualDTO> results = new List<ManualDTO>();

        List<Service_Manual__c> serviceManualRecords = [
            SELECT Id
            FROM Service_Manual__c
            WITH USER_MODE
            LIMIT 100
        ];

        if (serviceManualRecords.isEmpty()) return results;

        Set<Id> serviceManualIds = new Set<Id>();

        for (Service_Manual__c manualRecord : serviceManualRecords) {
            serviceManualIds.add(manualRecord.Id);
        }

        List<ContentDocumentLink> documentLinks = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :serviceManualIds
            WITH USER_MODE
        ];

        if (documentLinks.isEmpty()) return results;

        Set<Id> contentDocumentIds = new Set<Id>();

        for (ContentDocumentLink documentLink : documentLinks) {
            if (documentLink.ContentDocumentId != null) {
                contentDocumentIds.add(documentLink.ContentDocumentId);
            }
        }

        if (contentDocumentIds.isEmpty()) return results;

        List<ContentDocument> documents = [
            SELECT
                Id,
                Title,
                FileType,
                LatestPublishedVersionId
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
                AND FileType = 'PDF'
                AND Title IN :FEATURED_MANUAL_TITLES
            WITH USER_MODE
        ];

        Map<String, ContentDocument> documentsByTitle =
            new Map<String, ContentDocument>();

        for (ContentDocument documentRecord : documents) {
            if (!documentsByTitle.containsKey(documentRecord.Title)) {
                documentsByTitle.put(
                    documentRecord.Title,
                    documentRecord
                );
            }
        }

        /*
         * Iterate over FEATURED_MANUAL_TITLES so the homepage always
         * keeps the intended Ceramill → Roland display order.
         */
        for (String manualTitle : FEATURED_MANUAL_TITLES) {
            if (!documentsByTitle.containsKey(manualTitle)) continue;

            ContentDocument documentRecord =
                documentsByTitle.get(manualTitle);

            ManualDTO manual = new ManualDTO();

            manual.contentDocumentId = documentRecord.Id;
            manual.contentVersionId =
                documentRecord.LatestPublishedVersionId;

            manual.title = documentRecord.Title;
            manual.fileType = documentRecord.FileType;

            results.add(manual);
        }

        return results;
    }


    // =========================================================
    // General Helpers
    // =========================================================

    private static String buildMachineLabel(
        String manufacturer,
        String model
    ) {
        List<String> values = new List<String>();

        if (!String.isBlank(manufacturer)) {
            values.add(manufacturer.trim());
        }

        if (!String.isBlank(model)) {
            values.add(model.trim());
        }

        return String.join(values, ' ');
    }

    private static String safeText(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }


    // =========================================================
    // DTOs
    // =========================================================

    public class TechnicianHomeData {
        @AuraEnabled public Id technicianId { get; set; }
        @AuraEnabled public String technicianName { get; set; }
        @AuraEnabled public String technicianFirstName { get; set; }
        @AuraEnabled public VisitDTO currentVisit { get; set; }
        @AuraEnabled public List<VisitDTO> upcomingVisits { get; set; }
        @AuraEnabled public List<ManualDTO> serviceManuals { get; set; }
        @AuraEnabled public List<SimilarRepairDTO> similarRepairs { get; set; }
    }

    public class VisitDTO {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Datetime workStartedDateTime { get; set; }
        @AuraEnabled public Boolean isInProgress { get; set; }

        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }
        @AuraEnabled public String recommendedTools { get; set; }

        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }

        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String contactPhone { get; set; }
        @AuraEnabled public String contactEmail { get; set; }

        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String machineLabel { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String machineStatus { get; set; }

        @AuraEnabled public Id caseId { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String caseSubject { get; set; }

        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String fullAddress { get; set; }

        @AuraEnabled public SimilarRepairDTO similarRepair { get; set; }
        @AuraEnabled public List<SimilarRepairDTO> similarRepairs { get; set; }
    }

    public class ManualDTO {
        @AuraEnabled public Id contentVersionId { get; set; }
        @AuraEnabled public Id contentDocumentId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileType { get; set; }
    }

    public class SimilarRepairDTO {
        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }

        // Maintenance Log evidence used by the Similar Repairs card.
        @AuraEnabled public String maintenanceLogName { get; set; }
        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String repairSummary { get; set; }

        // Retained for Upcoming Visits until that UI is updated.
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String caseSubject { get; set; }
        @AuraEnabled public String matchedKeywords { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }
    }
}