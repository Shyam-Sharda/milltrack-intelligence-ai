public with sharing class CustomerPortalHomeController {
    private static final Integer MAX_MACHINES = 50;
    private static final Integer MAX_SERVICE_REQUESTS = 50;
    private static final Integer MAX_WORK_ORDERS = 50;

    private static final Set<String> OPEN_CASE_STATUSES = new Set<String>{'New', 'Scheduled', 'In Progress', 'Waiting on Parts', 'Follow-Up Required'};
    private static final Set<String> ACTIVE_WORK_ORDER_STATUSES = new Set<String>{'Pending', 'Parts to Order', 'Waiting on Parts', 'Ready_to_Assign', 'Assigned', 'In Progress', 'Temporary Fix'};

    @AuraEnabled(cacheable=true)
    public static HomeData getHomeData() {
        try {
            Id currentUserId = UserInfo.getUserId();

            List<User> portalUsers = [
                SELECT Id, ContactId
                FROM User
                WHERE Id = :currentUserId
                WITH USER_MODE
                LIMIT 1
            ];

            if (portalUsers.isEmpty() || portalUsers[0].ContactId == null) {
                throw new AuraHandledException('Your MillTrack customer profile could not be loaded.');
            }

            Id contactId = portalUsers[0].ContactId;

            List<Contact> contacts = [
                SELECT Id, FirstName, AccountId
                FROM Contact
                WHERE Id = :contactId
                WITH USER_MODE
                LIMIT 1
            ];

            if (contacts.isEmpty() || contacts[0].AccountId == null) {
                throw new AuraHandledException('Your MillTrack customer account could not be loaded.');
            }

            Contact customerContact = contacts[0];
            Id accountId = customerContact.AccountId;
            HomeData homeData = new HomeData();

            homeData.customerFirstName = customerContact.FirstName;

            loadMachines(homeData, accountId);
            loadServiceRequests(homeData, accountId);
            loadWorkOrders(homeData, accountId);

            return homeData;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Your MillTrack dashboard could not be loaded. Please refresh the page or try again later.');
        }
    }

    private static void loadMachines(HomeData homeData, Id accountId) {
        List<Asset> machines = [
            SELECT Id, Name, Manufacturer__c, Model__c, Serial_Number__c, Machine_Status__c, Install_Date__c, Last_Service_Date__c
            FROM Asset
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :MAX_MACHINES
        ];

        homeData.machineCount = machines.size();
        homeData.machines = new List<MachineSummary>();

        for (Asset machine : machines) {
            homeData.machines.add(new MachineSummary(machine));
        }
    }

    private static void loadServiceRequests(HomeData homeData, Id accountId) {
        List<Case> serviceRequests = [
            SELECT Id, CaseNumber, Subject, AssetId, Asset.Name, Status, Priority, CreatedDate, LastModifiedDate
            FROM Case
            WHERE AccountId = :accountId AND Status IN :OPEN_CASE_STATUSES
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :MAX_SERVICE_REQUESTS
        ];

        homeData.openServiceRequestCount = serviceRequests.size();
        homeData.serviceRequests = new List<ServiceRequestSummary>();

        for (Case serviceRequest : serviceRequests) {
            homeData.serviceRequests.add(new ServiceRequestSummary(serviceRequest));
        }
    }

    private static void loadWorkOrders(HomeData homeData, Id accountId) {
        List<WorkOrder> workOrders = [
            SELECT Id, WorkOrderNumber, Subject, AssetId, Asset.Name, Dispatch_Status__c, Scheduled_Visit__c, CreatedDate, LastModifiedDate
            FROM WorkOrder
            WHERE AccountId = :accountId AND Dispatch_Status__c IN :ACTIVE_WORK_ORDER_STATUSES
            WITH USER_MODE
            ORDER BY Scheduled_Visit__c ASC NULLS LAST, CreatedDate DESC
            LIMIT :MAX_WORK_ORDERS
        ];

        homeData.activeWorkOrderCount = workOrders.size();
        homeData.workOrders = new List<WorkOrderSummary>();

        for (WorkOrder workOrderRecord : workOrders) {
            homeData.workOrders.add(new WorkOrderSummary(workOrderRecord));
        }
    }

    private static String getCustomerWorkOrderStatus(String dispatchStatus) {
        switch on dispatchStatus {
            when 'Pending' { return 'Request Received'; }
            when 'Parts to Order' { return 'Waiting on Parts'; }
            when 'Waiting on Parts' { return 'Waiting on Parts'; }
            when 'Ready_to_Assign' { return 'Under Review'; }
            when 'Assigned' { return 'Visit Scheduled'; }
            when 'In Progress' { return 'Service in Progress'; }
            when 'Temporary Fix' { return 'Service in Progress'; }
            when 'Completed' { return 'Completed'; }
            when 'Cancelled' { return 'Service Cancelled'; }
            when else { return 'Under Review'; }
        }
    }

    public class HomeData {
        @AuraEnabled public String customerFirstName { get; set; }
        @AuraEnabled public Integer machineCount { get; set; }
        @AuraEnabled public Integer openServiceRequestCount { get; set; }
        @AuraEnabled public Integer activeWorkOrderCount { get; set; }
        @AuraEnabled public List<MachineSummary> machines { get; set; }
        @AuraEnabled public List<ServiceRequestSummary> serviceRequests { get; set; }
        @AuraEnabled public List<WorkOrderSummary> workOrders { get; set; }

        public HomeData() {
            customerFirstName = '';
            machineCount = 0; 
            openServiceRequestCount = 0; 
            activeWorkOrderCount = 0;
            machines = new List<MachineSummary>(); serviceRequests = new List<ServiceRequestSummary>(); workOrders = new List<WorkOrderSummary>();
        }
    }

    public class MachineSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Date installDate { get; set; }
        @AuraEnabled public Date lastServiceDate { get; set; }

        public MachineSummary(Asset machine) {
            id = machine.Id; 
            name = machine.Name; 
            manufacturer = machine.Manufacturer__c; 
            model = machine.Model__c;
            serialNumber = machine.Serial_Number__c; 
            status = machine.Machine_Status__c;
            installDate = machine.Install_Date__c; 
            lastServiceDate = machine.Last_Service_Date__c;
        }
    }

    public class ServiceRequestSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }

        public ServiceRequestSummary(Case serviceRequest) {
            id = serviceRequest.Id; 
            caseNumber = serviceRequest.CaseNumber; 
            subject = serviceRequest.Subject; 
            assetId = serviceRequest.AssetId;
            assetName = serviceRequest.Asset == null ? null : serviceRequest.Asset.Name;
            status = serviceRequest.Status; 
            priority = serviceRequest.Priority;
            createdDate = serviceRequest.CreatedDate; 
            lastModifiedDate = serviceRequest.LastModifiedDate;
        }
    }

    public class WorkOrderSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String customerStatus { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }

        public WorkOrderSummary(WorkOrder workOrderRecord) {
            id = workOrderRecord.Id; 
            workOrderNumber = workOrderRecord.WorkOrderNumber; 
            subject = workOrderRecord.Subject;
            assetId = workOrderRecord.AssetId; 
            assetName = workOrderRecord.Asset == null ? null : workOrderRecord.Asset.Name;
            dispatchStatus = workOrderRecord.Dispatch_Status__c; 
            customerStatus = getCustomerWorkOrderStatus(workOrderRecord.Dispatch_Status__c);
            scheduledVisit = workOrderRecord.Scheduled_Visit__c; 
            createdDate = workOrderRecord.CreatedDate; 
            lastModifiedDate = workOrderRecord.LastModifiedDate;
        }
    }
}