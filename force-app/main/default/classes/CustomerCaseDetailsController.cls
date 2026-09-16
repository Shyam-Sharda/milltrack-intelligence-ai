/**
 * Supplies customer-safe Case details, related machine information,
 * and the latest related Work Order for the MillTrack Experience
 * Cloud customer portal.
 */
public with sharing class CustomerCaseDetailsController {

    // =========================================================
    // Case Details
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static CaseDetailsData getCaseDetails(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('A Case ID is required.');
        }

        try {
            CustomerContext customerContext = getCustomerContext();
            Case authorizedCase = getAuthorizedCase(caseId, customerContext.accountId);

            if (authorizedCase == null) {
                throw new AuraHandledException(
                    'We could not verify this service request for your MillTrack account.'
                );
            }

            CaseDetailsData result = new CaseDetailsData();
            result.serviceRequest = new CaseSummary(authorizedCase);
            result.machine = buildMachineSummary(authorizedCase);
            result.serviceVisit = getLatestServiceVisit(authorizedCase.Id, customerContext.accountId);

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your service request information could not be loaded. Please refresh the page or try again later.'
            );
        }
    }


    // =========================================================
    // Customer Authorization
    // =========================================================

    private static CustomerContext getCustomerContext() {
        Id currentUserId = UserInfo.getUserId();

        List<User> portalUsers = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :currentUserId
            WITH USER_MODE
            LIMIT 1
        ];

        if (portalUsers.isEmpty() || portalUsers[0].ContactId == null) {
            throw new AuraHandledException(
                'Your MillTrack customer profile could not be loaded.'
            );
        }

        Id contactId = portalUsers[0].ContactId;

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];

        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new AuraHandledException(
                'Your MillTrack customer account could not be loaded.'
            );
        }

        CustomerContext customerContext = new CustomerContext();
        customerContext.contactId = contacts[0].Id;
        customerContext.accountId = contacts[0].AccountId;

        return customerContext;
    }


    // =========================================================
    // Authorized Case
    // =========================================================

    private static Case getAuthorizedCase(Id caseId, Id accountId) {
        List<Case> cases = [
            SELECT
                Id,
                CaseNumber,
                Status,
                Priority,
                Subject,
                Description,
                Error_Code__c,
                Technician_Requested__c,
                CreatedDate,
                ClosedDate,
                SLA_Due_Date__c,
                AssetId,
                Asset.Name,
                Asset.Manufacturer__c,
                Asset.Model__c,
                Asset.Serial_Number__c,
                Asset.Machine_Status__c,
                Asset.Portal_Image_Path__c
            FROM Case
            WHERE Id = :caseId
            AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return cases.isEmpty() ? null : cases[0];
    }


    // =========================================================
    // Related Machine
    // =========================================================

    private static MachineSummary buildMachineSummary(Case serviceRequest) {
        if (serviceRequest.AssetId == null || serviceRequest.Asset == null) {
            return null;
        }

        MachineSummary machine = new MachineSummary();
        machine.id = serviceRequest.AssetId;
        machine.name = serviceRequest.Asset.Name;
        machine.manufacturer = serviceRequest.Asset.Manufacturer__c;
        machine.model = serviceRequest.Asset.Model__c;
        machine.serialNumber = serviceRequest.Asset.Serial_Number__c;
        machine.status = serviceRequest.Asset.Machine_Status__c;
        machine.portalImagePath = serviceRequest.Asset.Portal_Image_Path__c;

        return machine;
    }


    // =========================================================
    // Related Work Order
    // =========================================================

    private static ServiceVisitSummary getLatestServiceVisit(Id caseId, Id accountId) {
        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Dispatch_Status__c,
                Subject,
                CreatedDate
            FROM WorkOrder
            WHERE CaseId = :caseId
            AND AccountId = :accountId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (workOrders.isEmpty()) {
            return null;
        }

        return new ServiceVisitSummary(workOrders[0]);
    }


    // =========================================================
    // Customer-Friendly Case Status
    // =========================================================

    private static String getCustomerCaseStatus(String status) {
        if (String.isBlank(status)) return 'Request Received';

        switch on status {
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
                return status;
            }
        }
    }


    // =========================================================
    // Customer-Friendly Work Order Status
    // Dispatch_Status__c is the authoritative Work Order status
    // in MillTrack.
    // =========================================================

    private static String getCustomerWorkOrderStatus(String dispatchStatus) {
        if (String.isBlank(dispatchStatus)) return 'Request Received';

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
                return 'Temporary Fix Applied';
            }

            when 'Completed' {
                return 'Completed';
            }

            when 'Cancelled' {
                return 'Service Cancelled';
            }

            when else {
                return dispatchStatus;
            }
        }
    }


    // =========================================================
    // Internal Context
    // =========================================================

    private class CustomerContext {
        public Id contactId;
        public Id accountId;
    }


    // =========================================================
    // Response Wrappers
    // =========================================================

    public class CaseDetailsData {
        @AuraEnabled public CaseSummary serviceRequest { get; set; }
        @AuraEnabled public MachineSummary machine { get; set; }
        @AuraEnabled public ServiceVisitSummary serviceVisit { get; set; }
    }


    public class CaseSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        @AuraEnabled public Boolean technicianRequested { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime closedDate { get; set; }
        @AuraEnabled public Datetime slaDueDate { get; set; }
        @AuraEnabled public Id assetId { get; set; }

        public CaseSummary(Case serviceRequest) {
            id = serviceRequest.Id;
            caseNumber = serviceRequest.CaseNumber;
            status = serviceRequest.Status;
            customerStatus = getCustomerCaseStatus(serviceRequest.Status);
            priority = serviceRequest.Priority;
            subject = serviceRequest.Subject;
            description = serviceRequest.Description;
            errorCode = serviceRequest.Error_Code__c;
            technicianRequested = serviceRequest.Technician_Requested__c;
            createdDate = serviceRequest.CreatedDate;
            closedDate = serviceRequest.ClosedDate;
            slaDueDate = serviceRequest.SLA_Due_Date__c;
            assetId = serviceRequest.AssetId;
        }
    }


    public class MachineSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String portalImagePath { get; set; }
    }


    public class ServiceVisitSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }

        public ServiceVisitSummary(WorkOrder workOrder) {
            id = workOrder.Id;
            workOrderNumber = workOrder.WorkOrderNumber;
            dispatchStatus = workOrder.Dispatch_Status__c;
            customerStatus = getCustomerWorkOrderStatus(workOrder.Dispatch_Status__c);
            subject = workOrder.Subject;
            createdDate = workOrder.CreatedDate;
        }
    }
}