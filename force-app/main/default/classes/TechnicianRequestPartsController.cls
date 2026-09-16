public with sharing class TechnicianRequestPartsController {

    public class RequestContext {
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public Decimal currentLaborHours { get; set; }
    }

    public class PartOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String compatibleModel { get; set; }
    }

    public class PartRequestInput {
        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public Integer quantity { get; set; }
    }

    public class SubmitResult {
        @AuraEnabled public Id workOrderPartId { get; set; }       // legacy/single-part compatibility
        @AuraEnabled public List<Id> workOrderPartIds { get; set; }
        @AuraEnabled public Integer requestedPartCount { get; set; }
        @AuraEnabled public Id maintenanceLogId { get; set; }
        @AuraEnabled public String workOrderStatus { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
        @AuraEnabled public Boolean notificationSent { get; set; }
        @AuraEnabled public String notificationWarning { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static RequestContext getRequestContext(Id workOrderId) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order is required.');

        WorkOrder wo = [
            SELECT Id, WorkOrderNumber, Subject, AssetId, Asset.Name, Asset.Manufacturer__c,
                   Asset.Model__c, Dispatch_Status__c, OwnerId, Labor_Hours__c
            FROM WorkOrder WHERE Id = :workOrderId LIMIT 1
        ];

        assertEligible(wo);
        getManagerQueueId();

        RequestContext r = new RequestContext();
        r.workOrderId = wo.Id; r.workOrderNumber = wo.WorkOrderNumber; r.subject = wo.Subject; r.assetId = wo.AssetId;
        r.assetName = wo.AssetId == null ? null : wo.Asset.Name; r.manufacturer = wo.AssetId == null ? null : wo.Asset.Manufacturer__c;
        r.model = wo.AssetId == null ? null : wo.Asset.Model__c; r.currentLaborHours = wo.Labor_Hours__c == null ? 0 : wo.Labor_Hours__c;
        return r;
    }

    // Kept temporarily so the current single-part LWC continues working.
    @AuraEnabled(cacheable=true)
    public static List<PartOption> getParts(String searchTerm, String manufacturer) {
        return queryParts(searchTerm, manufacturer);
    }

    // New wizard should use this method. Manufacturer comes from the Work Order Asset,
    // so the browser cannot request another manufacturer's catalog.
    @AuraEnabled(cacheable=true)
    public static List<PartOption> getManufacturerParts(Id workOrderId, String searchTerm) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order is required.');

        WorkOrder wo = [
            SELECT Id, AssetId, Asset.Manufacturer__c, Dispatch_Status__c, OwnerId
            FROM WorkOrder WHERE Id = :workOrderId LIMIT 1
        ];

        assertEligible(wo);
        if (wo.AssetId == null || String.isBlank(wo.Asset.Manufacturer__c))
            throw new AuraHandledException('The Work Order machine does not have a manufacturer.');

        return queryParts(searchTerm, wo.Asset.Manufacturer__c);
    }

    private static List<PartOption> queryParts(String searchTerm, String manufacturer) {
        List<Part_Catalog__c> records = String.isBlank(manufacturer)
            ? [SELECT Id, Name, Part_Number__c, Manufacturer__c, Compatible_Model__c, Keyword_Aliases__c
               FROM Part_Catalog__c WHERE Active__c = true ORDER BY Name LIMIT 500]
            : [SELECT Id, Name, Part_Number__c, Manufacturer__c, Compatible_Model__c, Keyword_Aliases__c
               FROM Part_Catalog__c WHERE Active__c = true AND Manufacturer__c = :manufacturer ORDER BY Name LIMIT 500];

        String term = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        List<PartOption> result = new List<PartOption>();

        for (Part_Catalog__c p : records) {
            String searchable = (p.Name == null ? '' : p.Name) + ' ' +
                                (p.Part_Number__c == null ? '' : p.Part_Number__c) + ' ' +
                                (p.Keyword_Aliases__c == null ? '' : p.Keyword_Aliases__c);

            if (term != null && !searchable.toLowerCase().contains(term)) continue;

            PartOption o = new PartOption();
            o.id = p.Id; o.name = p.Name; o.partNumber = p.Part_Number__c;
            o.manufacturer = p.Manufacturer__c; o.compatibleModel = p.Compatible_Model__c;
            result.add(o);
        }
        return result;
    }

    // Existing single-part LWC remains functional until we replace it.
    @AuraEnabled
    public static SubmitResult submitPartsRequest(
        Id workOrderId, Id partCatalogId, Integer quantity, String requestReason,
        String visitSummary, Decimal laborHours, Boolean temporaryRepairApplied
    ) {
        PartRequestInput p = new PartRequestInput();
        p.partCatalogId = partCatalogId; p.quantity = quantity;

        return submitPartsRequestV2(
            workOrderId,
            new List<PartRequestInput>{ p },
            requestReason,
            visitSummary,
            laborHours,
            temporaryRepairApplied
        );
    }

    // New multi-part wizard method.
    @AuraEnabled
    public static SubmitResult submitPartsRequestV2(
        Id workOrderId, List<PartRequestInput> parts, String requestReason,
        String visitSummary, Decimal laborHours, Boolean temporaryRepairApplied
    ) {
        validateInputs(workOrderId, parts, requestReason, visitSummary, laborHours);

        Savepoint sp = Database.setSavepoint();
        String stage = 'Starting request';

        try {
            stage = 'Loading Work Order';
            WorkOrder wo = [
                SELECT Id, WorkOrderNumber, CaseId, AssetId, Asset.Manufacturer__c, OwnerId,
                       Service_Manager__c, Dispatch_Status__c, Scheduled_Visit__c,
                       Suggested_Technician__c, Labor_Hours__c, Technician_Notes__c,
                       Problem_Summary__c
                FROM WorkOrder WHERE Id = :workOrderId LIMIT 1 FOR UPDATE
            ];

            assertEligible(wo);

            if (wo.AssetId == null || String.isBlank(wo.Asset.Manufacturer__c))
                throw new AuraHandledException('The Work Order machine does not have a manufacturer.');

            stage = 'Loading Service Manager Queue';
            Id managerQueueId = getManagerQueueId();

            Set<Id> ids = new Set<Id>();
            for (PartRequestInput p : parts) {
                if (p == null || p.partCatalogId == null) throw new AuraHandledException('Every requested part must have a Part Catalog selection.');
                if (p.quantity == null || p.quantity <= 0) throw new AuraHandledException('Every requested part must have a quantity greater than zero.');
                if (ids.contains(p.partCatalogId)) throw new AuraHandledException('The same part cannot be requested more than once.');
                ids.add(p.partCatalogId);
            }

            stage = 'Loading Part Catalog';
            Map<Id, Part_Catalog__c> catalog = new Map<Id, Part_Catalog__c>([
                SELECT Id, Name, Part_Number__c, Manufacturer__c, Active__c
                FROM Part_Catalog__c WHERE Id IN :ids
            ]);

            if (catalog.size() != ids.size()) throw new AuraHandledException('One or more selected parts could not be found.');

            String reason = requestReason.trim(), summary = visitSummary.trim();
            String tempText = temporaryRepairApplied == true ? 'Yes' : 'No';
            List<Work_Order_Part__c> wops = new List<Work_Order_Part__c>();
            List<String> partNoteSections = new List<String>(), partSummaryLines = new List<String>();

            for (PartRequestInput input : parts) {
                Part_Catalog__c part = catalog.get(input.partCatalogId);

                if (!part.Active__c) throw new AuraHandledException(part.Name + ' is no longer active in the Part Catalog.');
                if (part.Manufacturer__c != wo.Asset.Manufacturer__c)
                    throw new AuraHandledException(part.Name + ' does not belong to the ' + wo.Asset.Manufacturer__c + ' Part Catalog.');

                wops.add(new Work_Order_Part__c(
                    Work_Order__c = wo.Id, Machine__c = wo.AssetId, Part_Catalog__c = part.Id,
                    Quantity__c = input.quantity, Notes__c = reason, Order_Status__c = 'Requested',
                    Technician_Requested__c = true
                ));

                partNoteSections.add('Part: ' + part.Name + '\nQuantity: ' + input.quantity);
                partSummaryLines.add(part.Name + ' x ' + input.quantity);
            }

            stage = 'Creating Work Order Parts';
            insert wops;

            String partsForNotes = String.join(partNoteSections, '\n\n');
            String partsSummary = String.join(partSummaryLines, '\n');

            stage = 'Creating Maintenance Log';
            Maintenance_Log__c log = new Maintenance_Log__c(
                Asset__c = wo.AssetId, Work_Order__c = wo.Id, Maintenance_Date__c = Date.today(),
                Maintenance_Type__c = temporaryRepairApplied == true ? 'Temporary Repair' : 'Inspection',
                Problem_Summary__c = wo.Problem_Summary__c,
                Summary__c = summary,
                Technician_Notes__c = 'PARTS REQUEST\n\n' + partsForNotes + '\n\nReason: ' + reason +
                                     '\nTemporary Repair Applied: ' + tempText,
                Labor_Hours__c = laborHours, Issue_Resolved__c = false,
                Follow_Up_Required__c = true, Performed_By__c = UserInfo.getUserId()
            );
            insert log;

            Decimal existingLabor = wo.Labor_Hours__c == null ? 0 : wo.Labor_Hours__c;
            String visitNote =
                'PARTS REQUEST VISIT - ' + Date.today() +
                '\n\nVisit Summary:\n' + summary +
                '\n\nRequested Parts:\n' + partsSummary +
                '\n\nReason: ' + reason +
                '\nTemporary Repair Applied: ' + tempText +
                '\nLabor: ' + laborHours + ' hours';

            WorkOrder woUpdate = new WorkOrder(
                Id = wo.Id,
                Dispatch_Status__c = 'Waiting on Parts',
                OwnerId = managerQueueId,
                Scheduled_Visit__c = null,
                Suggested_Technician__c = null,
                Labor_Hours__c = existingLabor + laborHours,
                Technician_Notes__c = String.isBlank(wo.Technician_Notes__c)
                    ? visitNote
                    : wo.Technician_Notes__c + '\n\n' + visitNote
            );

            stage = 'Updating Work Order';
            Database.update(woUpdate, AccessLevel.SYSTEM_MODE);

            String caseStatus;
            if (wo.CaseId != null) {
                stage = 'Updating Case';
                Database.update(
                    new Case(Id = wo.CaseId, Status = 'Waiting on Parts'),
                    AccessLevel.SYSTEM_MODE
                );
                caseStatus = 'Waiting on Parts';
            }

            Boolean notificationSent = false;
            String notificationWarning;

            if (wo.Service_Manager__c != null) {
                try {
                    stage = 'Sending Manager Notification';
                    List<CustomNotificationType> types = [
                        SELECT Id FROM CustomNotificationType
                        WHERE DeveloperName = 'Parts_Request' LIMIT 1
                    ];

                    if (!types.isEmpty()) {
                        User tech = [SELECT FirstName, LastName FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

                        String notificationParts = partsSummary.length() > 350
                            ? partsSummary.left(347) + '...'
                            : partsSummary;

                        Messaging.CustomNotification n = new Messaging.CustomNotification();
                        n.setTitle('Parts Requested - Work Order ' + wo.WorkOrderNumber);
                        n.setBody(
                            tech.FirstName + ' ' + tech.LastName + ' requested ' + parts.size() +
                            (parts.size() == 1 ? ' part' : ' parts') + '.\n\n' +
                            notificationParts + '\n\nThe Work Order is now waiting on parts.'
                        );
                        n.setNotificationTypeId(types[0].Id);
                        n.setTargetId(wo.Id);
                        n.send(new Set<String>{ String.valueOf(wo.Service_Manager__c) });
                        notificationSent = true;
                    } else notificationWarning = 'The request was saved, but the Parts Request notification type could not be found.';
                } catch (Exception notificationException) {
                    notificationWarning = 'The request was saved, but the Service Manager could not be notified directly.';
                }
            } else {
                notificationWarning = 'The Work Order was returned to the Service Manager Queue, but no individual Service Manager was available for direct notification.';
            }

            List<Id> wopIds = new List<Id>();
            for (Work_Order_Part__c wop : wops) wopIds.add(wop.Id);

            SubmitResult r = new SubmitResult();
            r.workOrderPartId = wopIds.isEmpty() ? null : wopIds[0];
            r.workOrderPartIds = wopIds;
            r.requestedPartCount = wopIds.size();
            r.maintenanceLogId = log.Id;
            r.workOrderStatus = 'Waiting on Parts';
            r.caseStatus = caseStatus;
            r.notificationSent = notificationSent;
            r.notificationWarning = notificationWarning;
            return r;

        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'REQUEST PARTS ERROR [' + stage + ']: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            throw new AuraHandledException('We couldn\'t submit the parts request. No changes were saved. Please try again or contact your Service Manager.');
        }
    }

    private static void validateInputs(
        Id workOrderId, List<PartRequestInput> parts, String reason,
        String summary, Decimal laborHours
    ) {
        if (workOrderId == null) throw new AuraHandledException('A Work Order is required.');
        if (parts == null || parts.isEmpty()) throw new AuraHandledException('Select at least one part.');
        if (parts.size() > 25) throw new AuraHandledException('A maximum of 25 parts can be requested at one time.');
        if (String.isBlank(reason)) throw new AuraHandledException('Enter a reason for the parts request.');
        if (String.isBlank(summary)) throw new AuraHandledException('Enter a summary of the service visit.');
        if (laborHours == null || laborHours < 0) throw new AuraHandledException('Enter valid labor hours.');
    }

    private static void assertEligible(WorkOrder wo) {
        if (wo.Dispatch_Status__c != 'In Progress')
            throw new AuraHandledException('Parts can only be requested while the Work Order is In Progress.');
        if (wo.OwnerId != UserInfo.getUserId())
            throw new AuraHandledException('Only the technician currently assigned to this Work Order can request parts.');
    }

    private static Id getManagerQueueId() {
        List<Group> queues = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Service_Manager_Queue'
            LIMIT 1
        ];
        if (queues.isEmpty())
            throw new AuraHandledException('The Service Manager Queue could not be found. Contact your Salesforce administrator.');
        return queues[0].Id;
    }
}