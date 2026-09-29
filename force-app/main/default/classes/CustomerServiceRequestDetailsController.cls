public with sharing class CustomerServiceRequestDetailsController {
    @AuraEnabled(cacheable=true)
    public static ServiceRequestDetailsData getServiceRequestDetails(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('A Service Request ID is required.');
        }

        try {
            CustomerContext customerContext = getCustomerContext();
            Case serviceRequest = getAuthorizedCase(caseId, customerContext.accountId);

            if (serviceRequest == null) {
                throw new AuraHandledException(
                    'We could not verify this service request for your MillTrack account.'
                );
            }

            WorkOrder serviceVisit = getRelatedWorkOrder(serviceRequest.Id, customerContext.accountId);

            ServiceRequestDetailsData result = new ServiceRequestDetailsData();
            result.serviceRequest = new ServiceRequestSummary(serviceRequest, serviceVisit);
            result.machine = buildMachineSummary(serviceRequest);
            result.serviceVisit = serviceVisit == null ? null : new ServiceVisitSummary(serviceVisit);
            result.progress = buildProgress(serviceRequest, serviceVisit);
            result.resolution = serviceVisit != null && serviceVisit.Dispatch_Status__c == 'Completed' ? getResolution(serviceVisit.Id) : null;

            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'Your service request information could not be loaded. Please refresh the page or try again later.'
            );
        }
    }

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

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :portalUsers[0].ContactId
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

    private static Case getAuthorizedCase(Id caseId, Id accountId) {
        List<Case> serviceRequests = [
            SELECT Id, CaseNumber, Status, Priority, Subject,
                Description, Error_Code__c, CreatedDate,
                ClosedDate, LastModifiedDate, AssetId,
                Asset.Name, Asset.Manufacturer__c,
                Asset.Model__c, Asset.Serial_Number__c,
                Asset.Machine_Status__c,
                Asset.Portal_Image_Path__c
            FROM Case
            WHERE Id = :caseId
            AND AccountId = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        return serviceRequests.isEmpty() ? null : serviceRequests[0];
    }

    private static WorkOrder getRelatedWorkOrder(Id caseId, Id accountId) {
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AccountId,
                AssetId, CaseId, Dispatch_Status__c,
                Scheduled_Visit__c,
                Work_Started_Date_Time__c,
                Work_Ended_Date_Time__c,
                CreatedDate, LastModifiedDate
            FROM WorkOrder
            WHERE CaseId = :caseId
            AND AccountId = :accountId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return workOrders.isEmpty() ? null : workOrders[0];
    }

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

    private static ResolutionSummary getResolution(Id workOrderId) {
        List<Maintenance_Log__c> maintenanceLogs = [
            SELECT Id, Name, Maintenance_Date__c,
                Maintenance_Type__c, Summary__c,
                Root_Cause__c, Parts_Used__c,
                Labor_Hours__c, Work_Order__c,
                Issue_Resolved__c,
                Follow_Up_Required__c
            FROM Maintenance_Log__c
            WHERE Work_Order__c = :workOrderId
            WITH USER_MODE
            ORDER BY Maintenance_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];

        return maintenanceLogs.isEmpty()
            ? null
            : new ResolutionSummary(maintenanceLogs[0]);
    }

    private static ProgressData buildProgress(Case serviceRequest, WorkOrder serviceVisit) {
        String dispatchStatus = serviceVisit == null ? null : serviceVisit.Dispatch_Status__c;
        String currentStage = getCurrentStage(serviceRequest.Status, dispatchStatus);
        String message = getProgressMessage(currentStage, dispatchStatus);
        Boolean isCancelled = dispatchStatus == 'Cancelled';

        List<String> stageKeys = new List<String>{
            'requestReceived',
            'underReview',
            'visitScheduled',
            'serviceInProgress',
            'completed'
        };

        List<String> stageLabels = new List<String>{
            'Request Received',
            'Under Review',
            'Visit Scheduled',
            'Service in Progress',
            'Completed'
        };

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
        progress.message = message;
        progress.isCancelled = isCancelled;
        progress.stages = stages;
        return progress;
    }

    private static String getCurrentStage(String caseStatus, String dispatchStatus) {
        if (String.isNotBlank(dispatchStatus)) {
            switch on dispatchStatus {
                when 'Pending' {
                    return 'Request Received';
                }
                when 'Parts to Order' {
                    return 'Under Review';
                }
                when 'Waiting on Parts' {
                    return 'Under Review';
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
            when 'Closed' {
                return 'Completed';
            }
            when else {
                return 'Under Review';
            }
        }
    }

    private static String getProgressMessage(String currentStage, String dispatchStatus) {
        if (dispatchStatus == 'Parts to Order') {
            return 'MillTrack is arranging the parts needed for your service.';
        }

        if (dispatchStatus == 'Waiting on Parts') {
            return 'Your service request is waiting for the required parts to arrive.';
        }

        if (dispatchStatus == 'Temporary Fix') {
            return 'A temporary repair has been completed and additional service is being coordinated.';
        }

        switch on currentStage {
            when 'Request Received' {
                return 'Your service request has been received and is being reviewed by MillTrack.';
            }
            when 'Under Review' {
                return 'MillTrack is reviewing the reported issue and preparing the appropriate service response.';
            }
            when 'Visit Scheduled' {
                return 'A technician has been assigned and your service visit is scheduled.';
            }
            when 'Service in Progress' {
                return 'Your technician is actively working on the reported machine issue.';
            }
            when 'Completed' {
                return 'Your service has been completed.';
            }
            when 'Service Cancelled' {
                return 'This service visit has been cancelled.';
            }
            when else {
                return 'Your service request is being reviewed by MillTrack.';
            }
        }
    }

    private static Integer findStageIndex(List<String> stageLabels, String currentStage) {
        for (Integer index = 0; index < stageLabels.size(); index++) {
            if (stageLabels[index] == currentStage) {
                return index;
            }
        }

        return 1;
    }

    private static String getCustomerStatus(String caseStatus, String dispatchStatus) {
        if (String.isNotBlank(dispatchStatus)) {
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

    private static String determineResolutionOutcome(Boolean issueResolved, Boolean followUpRequired) {
        if (followUpRequired == true) {
            return 'Follow-up Required';
        }

        if (issueResolved == true) {
            return 'Resolved';
        }

        return 'Completed';
    }

    private class CustomerContext {
        public Id contactId;
        public Id accountId;
    }

    public class ServiceRequestDetailsData {
        @AuraEnabled public ServiceRequestSummary serviceRequest { get; set; }
        @AuraEnabled public MachineSummary machine { get; set; }
        @AuraEnabled public ServiceVisitSummary serviceVisit { get; set; }
        @AuraEnabled public ProgressData progress { get; set; }
        @AuraEnabled public ResolutionSummary resolution { get; set; }
    }

    public class ServiceRequestSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String caseStatus { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime closedDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public Id assetId { get; set; }

        public ServiceRequestSummary(Case serviceRequest, WorkOrder serviceVisit) {
            id = serviceRequest.Id;
            caseNumber = serviceRequest.CaseNumber;
            caseStatus = serviceRequest.Status;
            customerStatus = getCustomerStatus(
                serviceRequest.Status,
                serviceVisit == null ? null : serviceVisit.Dispatch_Status__c
            );
            priority = serviceRequest.Priority;
            subject = serviceRequest.Subject;
            description = serviceRequest.Description;
            errorCode = serviceRequest.Error_Code__c;
            createdDate = serviceRequest.CreatedDate;
            closedDate = serviceRequest.ClosedDate;
            lastModifiedDate = serviceRequest.LastModifiedDate;
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
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Datetime workStartedDateTime { get; set; }
        @AuraEnabled public Datetime workEndedDateTime { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }

        public ServiceVisitSummary(WorkOrder serviceVisit) {
            id = serviceVisit.Id;
            workOrderNumber = serviceVisit.WorkOrderNumber;
            dispatchStatus = serviceVisit.Dispatch_Status__c;
            scheduledVisit = serviceVisit.Scheduled_Visit__c;
            workStartedDateTime = serviceVisit.Work_Started_Date_Time__c;
            workEndedDateTime = serviceVisit.Work_Ended_Date_Time__c;
            createdDate = serviceVisit.CreatedDate;
        }
    }

    public class ProgressData {
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String currentStage { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isCancelled { get; set; }
        @AuraEnabled public List<ProgressStage> stages { get; set; }
    }

    public class ProgressStage {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String state { get; set; }
    }

    public class ResolutionSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String maintenanceNumber { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String maintenanceType { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String partsUsed { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public Boolean issueResolved { get; set; }
        @AuraEnabled public Boolean followUpRequired { get; set; }
        @AuraEnabled public String outcome { get; set; }

        public ResolutionSummary(Maintenance_Log__c maintenanceLog) {
            id = maintenanceLog.Id;
            maintenanceNumber = maintenanceLog.Name;
            maintenanceDate = maintenanceLog.Maintenance_Date__c;
            maintenanceType = maintenanceLog.Maintenance_Type__c;
            summary = maintenanceLog.Summary__c;
            rootCause = maintenanceLog.Root_Cause__c;
            partsUsed = maintenanceLog.Parts_Used__c;
            laborHours = maintenanceLog.Labor_Hours__c;
            issueResolved = maintenanceLog.Issue_Resolved__c;
            followUpRequired = maintenanceLog.Follow_Up_Required__c;
            outcome = determineResolutionOutcome(issueResolved, followUpRequired);
        }
    }
}