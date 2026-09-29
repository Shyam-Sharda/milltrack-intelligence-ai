public with sharing class CustomerServiceRequestListController {
    private static final Integer MAX_SERVICE_REQUESTS = 200;

    @AuraEnabled(cacheable=true)
    public static List<ServiceRequestSummary> getServiceRequests() {
        try {
            Id accountId = getCustomerAccountId();

            List<Case> serviceRequests = [
                SELECT Id, CaseNumber, Subject, AssetId, Asset.Name, Status,
                    Priority, CreatedDate, ClosedDate, LastModifiedDate
                FROM Case
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT :MAX_SERVICE_REQUESTS
            ];

            Set<Id> caseIds = new Set<Id>();

            for (Case serviceRequest : serviceRequests) {
                caseIds.add(serviceRequest.Id);
            }

            Map<Id, WorkOrder> workOrderByCaseId = new Map<Id, WorkOrder>();

            if (!caseIds.isEmpty()) {
                List<WorkOrder> workOrders = [
                    SELECT Id, CaseId, WorkOrderNumber, Dispatch_Status__c,
                        Scheduled_Visit__c, CreatedDate, LastModifiedDate
                    FROM WorkOrder
                    WHERE CaseId IN :caseIds
                    WITH USER_MODE
                ];

                for (WorkOrder workOrderRecord : workOrders) {
                    workOrderByCaseId.put(
                        workOrderRecord.CaseId,
                        workOrderRecord
                    );
                }
            }

            List<ServiceRequestSummary> results =
                new List<ServiceRequestSummary>();

            for (Case serviceRequest : serviceRequests) {
                WorkOrder relatedWorkOrder =
                    workOrderByCaseId.get(serviceRequest.Id);

                results.add(
                    new ServiceRequestSummary(
                        serviceRequest,
                        relatedWorkOrder
                    )
                );
            }

            return results;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your MillTrack service requests could not be loaded. Please refresh the page or try again later.'
            );
        }
    }

    private static Id getCustomerAccountId() {
        Id currentUserId = UserInfo.getUserId();

        List<User> portalUsers = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :currentUserId
            WITH USER_MODE
            LIMIT 1
        ];

        if (
            portalUsers.isEmpty() ||
            portalUsers[0].ContactId == null
        ) {
            throw new AuraHandledException(
                'Your MillTrack customer profile could not be loaded.'
            );
        }

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :portalUsers[0].ContactId
            WITH USER_MODE
            LIMIT 1
        ];

        if (
            contacts.isEmpty() ||
            contacts[0].AccountId == null
        ) {
            throw new AuraHandledException(
                'Your MillTrack customer account could not be loaded.'
            );
        }

        return contacts[0].AccountId;
    }

    private static String getCustomerServiceRequestStatus(
        String caseStatus,
        String dispatchStatus
    ) {
        if (String.isNotBlank(dispatchStatus)) {
            return getCustomerWorkOrderStatus(
                dispatchStatus
            );
        }

        switch on caseStatus {
            when 'New' {
                return 'Request Received';
            }
            when 'Scheduled' {
                return 'Visit Scheduled';
            }
            when 'In Progress' {
                return 'Service in Progress';
            }
            when 'Waiting on Parts' {
                return 'Waiting on Parts';
            }
            when 'Follow-Up Required' {
                return 'Follow-Up Required';
            }
            when 'Closed' {
                return 'Completed';
            }
            when else {
                return String.isBlank(caseStatus)
                    ? 'Request Received'
                    : caseStatus;
            }
        }
    }

    private static String getCustomerWorkOrderStatus(
        String dispatchStatus
    ) {
        switch on dispatchStatus {
            when 'Pending' {
                return 'Request Received';
            }
            when 'Parts to Order' {
                return 'Waiting on Parts';
            }
            when 'Waiting on Parts' {
                return 'Waiting on Parts';
            }
            when 'Ready_to_Assign' {
                return 'Under Review';
            }
            when 'Assigned' {
                return 'Visit Scheduled';
            }
            when 'In Progress' {
                return 'Service in Progress';
            }
            when 'Temporary Fix' {
                return 'Service in Progress';
            }
            when 'Completed' {
                return 'Completed';
            }
            when 'Cancelled' {
                return 'Service Cancelled';
            }
            when else {
                return 'Under Review';
            }
        }
    }

    public class ServiceRequestSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime closedDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }

        public ServiceRequestSummary(
            Case serviceRequest,
            WorkOrder relatedWorkOrder
        ) {
            id = serviceRequest.Id;
            caseNumber = serviceRequest.CaseNumber;
            subject = serviceRequest.Subject;
            assetId = serviceRequest.AssetId;
            assetName = serviceRequest.Asset == null
                ? null
                : serviceRequest.Asset.Name;
            caseStatus = serviceRequest.Status;
            priority = serviceRequest.Priority;
            createdDate = serviceRequest.CreatedDate;
            closedDate = serviceRequest.ClosedDate;
            lastModifiedDate = serviceRequest.LastModifiedDate;

            if (relatedWorkOrder != null) {
                workOrderId = relatedWorkOrder.Id;
                workOrderNumber =
                    relatedWorkOrder.WorkOrderNumber;
                dispatchStatus =
                    relatedWorkOrder.Dispatch_Status__c;
                scheduledVisit =
                    relatedWorkOrder.Scheduled_Visit__c;
            }

            customerStatus =
                getCustomerServiceRequestStatus(
                    serviceRequest.Status,
                    dispatchStatus
                );
        }
    }
}