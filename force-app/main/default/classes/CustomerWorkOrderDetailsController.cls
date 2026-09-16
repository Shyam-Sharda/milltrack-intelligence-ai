/**
 * Supplies customer-safe Work Order details, progress information,
 * related machine information, and the originating service request
 * for the MillTrack Experience Cloud customer portal.
 *
 * MillTrack uses Dispatch_Status__c as the authoritative
 * Work Order lifecycle status.
 */
public with sharing class CustomerWorkOrderDetailsController {

    // =========================================================
    // Work Order Details
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static WorkOrderDetailsData getWorkOrderDetails(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('A Work Order ID is required.');
        }

        try {
            CustomerContext customerContext = getCustomerContext();
            WorkOrder authorizedWorkOrder = getAuthorizedWorkOrder(
                workOrderId,
                customerContext.accountId
            );

            if (authorizedWorkOrder == null) {
                throw new AuraHandledException(
                    'We could not verify this service visit for your MillTrack account.'
                );
            }

            WorkOrderDetailsData result = new WorkOrderDetailsData();
            result.serviceVisit = new ServiceVisitSummary(authorizedWorkOrder);
            result.progress = buildProgress(authorizedWorkOrder);
            result.machine = buildMachineSummary(authorizedWorkOrder);
            result.serviceRequest = buildServiceRequestSummary(authorizedWorkOrder);

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your service visit information could not be loaded. Please refresh the page or try again later.'
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
    // Authorized Work Order
    // =========================================================

    private static WorkOrder getAuthorizedWorkOrder(Id workOrderId, Id accountId) {
        List<WorkOrder> workOrders = [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                AccountId,
                AssetId,
                CaseId,
                Dispatch_Status__c,
                Recommended_Solution__c,
                Scheduled_Visit__c,
                Suggested_Technician__c,
                Work_Started_Date_Time__c,
                Work_Ended_Date_Time__c,
                CreatedDate,
                Asset.Name,
                Asset.Manufacturer__c,
                Asset.Model__c,
                Asset.Serial_Number__c,
                Asset.Machine_Status__c,
                Asset.Portal_Image_Path__c,
                Case.CaseNumber,
                Case.Subject,
                Case.Status,
                Case.Priority,
                Case.CreatedDate
            FROM WorkOrder
            WHERE Id = :workOrderId
            AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return workOrders.isEmpty() ? null : workOrders[0];
    }


    // =========================================================
    // Machine
    // =========================================================

    private static MachineSummary buildMachineSummary(WorkOrder workOrderRecord) {
        if (workOrderRecord.AssetId == null || workOrderRecord.Asset == null) {
            return null;
        }

        MachineSummary machine = new MachineSummary();
        machine.id = workOrderRecord.AssetId;
        machine.name = workOrderRecord.Asset.Name;
        machine.manufacturer = workOrderRecord.Asset.Manufacturer__c;
        machine.model = workOrderRecord.Asset.Model__c;
        machine.serialNumber = workOrderRecord.Asset.Serial_Number__c;
        machine.status = workOrderRecord.Asset.Machine_Status__c;
        machine.portalImagePath = workOrderRecord.Asset.Portal_Image_Path__c;

        return machine;
    }


    // =========================================================
    // Related Service Request
    // =========================================================

    private static ServiceRequestSummary buildServiceRequestSummary(WorkOrder workOrderRecord) {
        if (workOrderRecord.CaseId == null || workOrderRecord.Case == null) {
            return null;
        }

        ServiceRequestSummary serviceRequest = new ServiceRequestSummary();
        serviceRequest.id = workOrderRecord.CaseId;
        serviceRequest.caseNumber = workOrderRecord.Case.CaseNumber;
        serviceRequest.subject = workOrderRecord.Case.Subject;
        serviceRequest.status = workOrderRecord.Case.Status;
        serviceRequest.customerStatus = getCustomerCaseStatus(workOrderRecord.Case.Status);
        serviceRequest.priority = workOrderRecord.Case.Priority;
        serviceRequest.createdDate = workOrderRecord.Case.CreatedDate;

        return serviceRequest;
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
    // Customer Progress
    //
    // Builds the customer-facing Work Order progress state.
    // Dispatch_Status__c is authoritative.
    // =========================================================

    private static ProgressData buildProgress(WorkOrder workOrderRecord) {
        String dispatchStatus = workOrderRecord.Dispatch_Status__c;

        if (String.isBlank(dispatchStatus)) {
            dispatchStatus = '';
        }

        Boolean showPartsStage =
            dispatchStatus == 'Parts to Order' ||
            dispatchStatus == 'Waiting on Parts';

        Boolean isCancelled = dispatchStatus == 'Cancelled';

        String currentStage;
        String customerMessage;

        switch on dispatchStatus {
            when 'Pending' {
                currentStage = 'Request Received';
                customerMessage = 'We received your service request.';
            }

            when 'Parts to Order' {
                currentStage = 'Waiting on Parts';
                customerMessage = 'Parts are being arranged for your service.';
            }

            when 'Waiting on Parts' {
                currentStage = 'Waiting on Parts';
                customerMessage = 'We are waiting for the required parts to arrive.';
            }

            when 'Ready_to_Assign' {
                currentStage = 'Under Review';
                customerMessage =
                    'Your service request has been reviewed and is being prepared for scheduling.';
            }

            when 'Assigned' {
                currentStage = 'Visit Scheduled';
                customerMessage =
                    'A technician has been assigned and your service visit is scheduled.';
            }

            when 'In Progress' {
                currentStage = 'Service in Progress';
                customerMessage =
                    'Your technician is currently working on this service.';
            }

            when 'Temporary Fix' {
                currentStage = 'Service in Progress';
                customerMessage =
                    'A temporary repair was completed. Additional service is being coordinated.';
            }

            when 'Completed' {
                currentStage = 'Completed';
                customerMessage = 'Your service has been completed.';
            }

            when 'Cancelled' {
                currentStage = 'Service Cancelled';
                customerMessage = 'This service work order has been cancelled.';
            }

            when else {
                currentStage = 'Under Review';
                customerMessage = 'Your service request is under review.';
            }
        }

        List<String> stageKeys = new List<String>{
            'requestReceived',
            'underReview'
        };

        List<String> stageLabels = new List<String>{
            'Request Received',
            'Under Review'
        };

        if (showPartsStage) {
            stageKeys.add('waitingOnParts');
            stageLabels.add('Waiting on Parts');
        }

        stageKeys.add('technicianAssigned');
        stageLabels.add('Technician Assigned');

        stageKeys.add('visitScheduled');
        stageLabels.add('Visit Scheduled');

        stageKeys.add('serviceInProgress');
        stageLabels.add('Service in Progress');

        stageKeys.add('completed');
        stageLabels.add('Completed');

        Integer currentStageIndex = findStageIndex(stageLabels, currentStage);
        List<ProgressStage> stages = new List<ProgressStage>();

        for (Integer index = 0; index < stageLabels.size(); index++) {
            String stageState = 'upcoming';

            if (isCancelled) {
                if (index == 0) {
                    stageState = 'completed';
                }
            } else if (index < currentStageIndex) {
                stageState = 'completed';
            } else if (index == currentStageIndex) {
                stageState = 'current';
            }

            ProgressStage stage = new ProgressStage();
            stage.key = stageKeys[index];
            stage.label = stageLabels[index];
            stage.state = stageState;

            stages.add(stage);
        }

        ProgressData progress = new ProgressData();
        progress.dispatchStatus = dispatchStatus;
        progress.currentStage = currentStage;
        progress.message = customerMessage;
        progress.isCancelled = isCancelled;
        progress.showPartsStage = showPartsStage;
        progress.stages = stages;

        return progress;
    }


    private static Integer findStageIndex(List<String> stageLabels, String currentStage) {
        for (Integer index = 0; index < stageLabels.size(); index++) {
            if (stageLabels[index] == currentStage) {
                return index;
            }
        }

        return 1;
    }


    // =========================================================
    // Internal Context
    // =========================================================

    private class CustomerContext {
        public Id contactId;
        public Id accountId;
    }


    // =========================================================
    // Response Wrapper
    // =========================================================

    public class WorkOrderDetailsData {
        @AuraEnabled public ServiceVisitSummary serviceVisit { get; set; }
        @AuraEnabled public ProgressData progress { get; set; }
        @AuraEnabled public MachineSummary machine { get; set; }
        @AuraEnabled public ServiceRequestSummary serviceRequest { get; set; }
    }


    // =========================================================
    // Service Visit
    // =========================================================

    public class ServiceVisitSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String recommendedSolution { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Id suggestedTechnicianId { get; set; }
        @AuraEnabled public String assignedTechnicianName { get; set; }
        @AuraEnabled public Datetime workStartedDateTime { get; set; }
        @AuraEnabled public Datetime workEndedDateTime { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public Id caseId { get; set; }

        public ServiceVisitSummary(WorkOrder workOrderRecord) {
            id = workOrderRecord.Id;
            workOrderNumber = workOrderRecord.WorkOrderNumber;
            subject = workOrderRecord.Subject;
            dispatchStatus = workOrderRecord.Dispatch_Status__c;
            recommendedSolution = workOrderRecord.Recommended_Solution__c;
            scheduledVisit = workOrderRecord.Scheduled_Visit__c;
            suggestedTechnicianId = workOrderRecord.Suggested_Technician__c;
            assignedTechnicianName = null;
            workStartedDateTime = workOrderRecord.Work_Started_Date_Time__c;
            workEndedDateTime = workOrderRecord.Work_Ended_Date_Time__c;
            createdDate = workOrderRecord.CreatedDate;
            assetId = workOrderRecord.AssetId;
            caseId = workOrderRecord.CaseId;
        }
    }


    // =========================================================
    // Machine
    // =========================================================

    public class MachineSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String portalImagePath { get; set; }
    }


    // =========================================================
    // Related Service Request
    // =========================================================

    public class ServiceRequestSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }


    // =========================================================
    // Progress
    // =========================================================

    public class ProgressData {
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String currentStage { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public Boolean showPartsStage { get; set; }
        @AuraEnabled public List<ProgressStage> stages { get; set; }
    }


    public class ProgressStage {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String state { get; set; }
    }
}