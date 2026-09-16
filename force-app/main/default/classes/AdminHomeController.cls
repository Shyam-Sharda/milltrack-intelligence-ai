public with sharing class AdminHomeController {

    private static final Integer RECENT_VIEWED_LIMIT = 6;
    private static final Integer CARD_RECORD_LIMIT = 5;


    // =========================================================
    // Home Data
    // =========================================================

    @AuraEnabled(cacheable=true)
    public static AdminHomeData getHomeData() {
        try {
            AdminHomeData data = new AdminHomeData();

            data.recentlyViewed = getRecentlyViewed();

            data.accounts = getRecentAccounts();
            data.contacts = getRecentContacts();
            data.assets = getRecentAssets();

            data.cases = getRecentCases();
            data.workOrders = getRecentWorkOrders();
            data.maintenanceLogs = getRecentMaintenanceLogs();

            data.partCatalogs = getRecentPartCatalogs();
            data.workOrderParts = getRecentWorkOrderParts();
            data.serviceManuals = getRecentServiceManuals();

            return data;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException(
                'The MillTrack admin workspace could not be loaded. Please refresh the page and try again.'
            );
        }
    }


    // =========================================================
    // Recently Viewed
    // =========================================================

    private static List<RecentlyViewedItem> getRecentlyViewed() {
        Set<String> supportedObjects = new Set<String>{
            'Account',
            'Contact',
            'Asset',
            'Case',
            'WorkOrder',
            'Maintenance_Log__c',
            'Part_Catalog__c',
            'Work_Order_Part__c',
            'Service_Manual__c'
        };

        List<RecentlyViewed> recentlyViewedRecords = [
            SELECT Id, Name, Type, LastViewedDate, LastReferencedDate
            FROM RecentlyViewed
            WHERE LastViewedDate != null
            ORDER BY LastViewedDate DESC
            LIMIT 40
        ];

        List<RecentlyViewedItem> results = new List<RecentlyViewedItem>();

        for (RecentlyViewed recentRecord : recentlyViewedRecords) {
            String objectApiName = recentRecord.Id.getSObjectType().getDescribe().getName();

            if (!supportedObjects.contains(objectApiName)) {
                continue;
            }

            RecentlyViewedItem item = new RecentlyViewedItem();
            item.id = recentRecord.Id;
            item.name = recentRecord.Name;
            item.objectApiName = objectApiName;
            item.objectLabel = recentRecord.Id.getSObjectType().getDescribe().getLabel();
            item.lastViewedDate = recentRecord.LastViewedDate;

            results.add(item);

            if (results.size() == RECENT_VIEWED_LIMIT) {
                break;
            }
        }

        return results;
    }


    // =========================================================
    // Customer Setup - Accounts
    // =========================================================

    private static List<AccountItem> getRecentAccounts() {
        List<AccountItem> results = new List<AccountItem>();

        for (Account accountRecord : [
            SELECT
                Id,
                Name,
                Phone,
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry,
                CreatedDate
            FROM Account
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            AccountItem item = new AccountItem();
            item.id = accountRecord.Id;
            item.name = accountRecord.Name;
            item.phone = accountRecord.Phone;
            item.billingAddress = formatBillingAddress(accountRecord);
            item.createdDate = accountRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Customer Setup - Contacts
    // =========================================================

    private static List<ContactItem> getRecentContacts() {
        List<ContactItem> results = new List<ContactItem>();

        for (Contact contactRecord : [
            SELECT
                Id,
                Name,
                MobilePhone,
                Email,
                AccountId,
                Account.Name,
                CreatedDate
            FROM Contact
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            ContactItem item = new ContactItem();
            item.id = contactRecord.Id;
            item.name = contactRecord.Name;
            item.mobile = contactRecord.MobilePhone;
            item.email = contactRecord.Email;
            item.accountId = contactRecord.AccountId;
            item.accountName = contactRecord.Account == null ? null : contactRecord.Account.Name;
            item.createdDate = contactRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Customer Setup - Assets
    // =========================================================

    private static List<AssetItem> getRecentAssets() {
        List<AssetItem> results = new List<AssetItem>();

        for (Asset assetRecord : [
            SELECT
                Id,
                Name,
                Manufacturer__c,
                Model__c,
                Serial_Number__c,
                AccountId,
                Account.Name,
                CreatedDate
            FROM Asset
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            AssetItem item = new AssetItem();
            item.id = assetRecord.Id;
            item.name = assetRecord.Name;
            item.manufacturer = assetRecord.Manufacturer__c;
            item.model = assetRecord.Model__c;
            item.serialNumber = assetRecord.Serial_Number__c;
            item.accountId = assetRecord.AccountId;
            item.accountName = assetRecord.Account == null ? null : assetRecord.Account.Name;
            item.createdDate = assetRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Service Operations - Cases
    // =========================================================

    private static List<CaseItem> getRecentCases() {
        List<CaseItem> results = new List<CaseItem>();

        for (Case caseRecord : [
            SELECT
                Id,
                CaseNumber,
                AccountId,
                Account.Name,
                AssetId,
                Asset.Name,
                Subject,
                Status,
                CreatedDate
            FROM Case
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            CaseItem item = new CaseItem();
            item.id = caseRecord.Id;
            item.caseNumber = caseRecord.CaseNumber;
            item.accountId = caseRecord.AccountId;
            item.accountName = caseRecord.Account == null ? null : caseRecord.Account.Name;
            item.assetId = caseRecord.AssetId;
            item.assetName = caseRecord.Asset == null ? null : caseRecord.Asset.Name;
            item.subject = caseRecord.Subject;
            item.status = caseRecord.Status;
            item.createdDate = caseRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Service Operations - Work Orders
    // =========================================================

    private static List<WorkOrderItem> getRecentWorkOrders() {
        List<WorkOrderItem> results = new List<WorkOrderItem>();

        for (WorkOrder workOrderRecord : [
            SELECT
                Id,
                WorkOrderNumber,
                Subject,
                AssetId,
                Asset.Name,
                Dispatch_Status__c,
                Scheduled_Visit__c,
                CreatedDate
            FROM WorkOrder
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            WorkOrderItem item = new WorkOrderItem();
            item.id = workOrderRecord.Id;
            item.workOrderNumber = workOrderRecord.WorkOrderNumber;
            item.subject = workOrderRecord.Subject;
            item.assetId = workOrderRecord.AssetId;
            item.assetName = workOrderRecord.Asset == null ? null : workOrderRecord.Asset.Name;
            item.dispatchStatus = workOrderRecord.Dispatch_Status__c;
            item.displayStatus = getWorkOrderDisplayStatus(workOrderRecord.Dispatch_Status__c);
            item.scheduledVisit = workOrderRecord.Scheduled_Visit__c;
            item.createdDate = workOrderRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Service Operations - Maintenance Logs
    // =========================================================

    private static List<MaintenanceLogItem> getRecentMaintenanceLogs() {
        List<MaintenanceLogItem> results = new List<MaintenanceLogItem>();

        for (Maintenance_Log__c maintenanceRecord : [
            SELECT
                Id,
                Name,
                Maintenance_Date__c,
                Root_Cause__c,
                Issue_Resolved__c,
                Follow_Up_Required__c,
                CreatedDate
            FROM Maintenance_Log__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            MaintenanceLogItem item = new MaintenanceLogItem();
            item.id = maintenanceRecord.Id;
            item.maintenanceNumber = maintenanceRecord.Name;
            item.maintenanceDate = maintenanceRecord.Maintenance_Date__c;
            item.rootCause = maintenanceRecord.Root_Cause__c;
            item.outcome = getMaintenanceOutcome(maintenanceRecord);
            item.createdDate = maintenanceRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Parts & Knowledge - Part Catalog
    // =========================================================

    private static List<PartCatalogItem> getRecentPartCatalogs() {
        List<PartCatalogItem> results = new List<PartCatalogItem>();

        for (Part_Catalog__c partRecord : [
            SELECT
                Id,
                Name,
                Part_Number__c,
                Manufacturer__c,
                Compatible_Model__c,
                CreatedDate
            FROM Part_Catalog__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            PartCatalogItem item = new PartCatalogItem();
            item.id = partRecord.Id;
            item.name = partRecord.Name;
            item.partNumber = partRecord.Part_Number__c;
            item.manufacturer = partRecord.Manufacturer__c;
            item.compatibleModel = partRecord.Compatible_Model__c;
            item.createdDate = partRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Parts & Knowledge - Work Order Parts
    // =========================================================

    private static List<WorkOrderPartItem> getRecentWorkOrderParts() {
        List<WorkOrderPartItem> results = new List<WorkOrderPartItem>();

        for (Work_Order_Part__c partRecord : [
            SELECT
                Id,
                Name,
                Part_Catalog__c,
                Part_Catalog__r.Name,
                Machine__c,
                Machine__r.Name,
                Work_Order__c,
                Work_Order__r.WorkOrderNumber,
                CreatedDate
            FROM Work_Order_Part__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            WorkOrderPartItem item = new WorkOrderPartItem();
            item.id = partRecord.Id;
            item.partNumber = partRecord.Name;
            item.partCatalogId = partRecord.Part_Catalog__c;
            item.partCatalogName =
                partRecord.Part_Catalog__r == null
                    ? null
                    : partRecord.Part_Catalog__r.Name;
            item.machineId = partRecord.Machine__c;
            item.machineName =
                partRecord.Machine__r == null
                    ? null
                    : partRecord.Machine__r.Name;
            item.workOrderId = partRecord.Work_Order__c;
            item.workOrderNumber =
                partRecord.Work_Order__r == null
                    ? null
                    : partRecord.Work_Order__r.WorkOrderNumber;
            item.createdDate = partRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Parts & Knowledge - Service Manuals
    // =========================================================

    private static List<ServiceManualItem> getRecentServiceManuals() {
        List<ServiceManualItem> results = new List<ServiceManualItem>();

        for (Service_Manual__c manualRecord : [
            SELECT
                Id,
                Name,
                Manufacturer__c,
                Model__c,
                Document_Type__c,
                CreatedDate
            FROM Service_Manual__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :CARD_RECORD_LIMIT
        ]) {
            ServiceManualItem item = new ServiceManualItem();
            item.id = manualRecord.Id;
            item.title = manualRecord.Name;
            item.manufacturer = manualRecord.Manufacturer__c;
            item.model = manualRecord.Model__c;
            item.documentType = manualRecord.Document_Type__c;
            item.createdDate = manualRecord.CreatedDate;

            results.add(item);
        }

        return results;
    }


    // =========================================================
    // Display Helpers
    // =========================================================

    private static String getWorkOrderDisplayStatus(String dispatchStatus) {
        if (String.isBlank(dispatchStatus)) {
            return 'Not Set';
        }

        switch on dispatchStatus {
            when 'Pending' {
                return 'Pending';
            }

            when 'Parts to Order' {
                return 'Parts to Order';
            }

            when 'Waiting on Parts' {
                return 'Waiting on Parts';
            }

            when 'Ready_to_Assign' {
                return 'Ready to Assign';
            }

            when 'Assigned' {
                return 'Assigned';
            }

            when 'In Progress' {
                return 'In Progress';
            }

            when 'Temporary Fix' {
                return 'Temporary Fix';
            }

            when 'Completed' {
                return 'Completed';
            }

            when 'Cancelled' {
                return 'Cancelled';
            }

            when else {
                return dispatchStatus;
            }
        }
    }

    private static String getMaintenanceOutcome(Maintenance_Log__c maintenanceRecord) {
        if (maintenanceRecord.Issue_Resolved__c == true) {
            return 'Issue Resolved';
        }

        if (maintenanceRecord.Follow_Up_Required__c == true) {
            return 'Follow-Up Required';
        }

        return 'Service Recorded';
    }

    private static String formatBillingAddress(Account accountRecord) {
        List<String> addressParts = new List<String>();

        if (String.isNotBlank(accountRecord.BillingStreet)) {
            addressParts.add(accountRecord.BillingStreet);
        }

        String cityStatePostal = '';

        if (String.isNotBlank(accountRecord.BillingCity)) {
            cityStatePostal = accountRecord.BillingCity;
        }

        if (String.isNotBlank(accountRecord.BillingState)) {
            cityStatePostal += String.isBlank(cityStatePostal)
                ? accountRecord.BillingState
                : ', ' + accountRecord.BillingState;
        }

        if (String.isNotBlank(accountRecord.BillingPostalCode)) {
            cityStatePostal += String.isBlank(cityStatePostal)
                ? accountRecord.BillingPostalCode
                : ' ' + accountRecord.BillingPostalCode;
        }

        if (String.isNotBlank(cityStatePostal)) {
            addressParts.add(cityStatePostal);
        }

        if (String.isNotBlank(accountRecord.BillingCountry)) {
            addressParts.add(accountRecord.BillingCountry);
        }

        return addressParts.isEmpty()
            ? null
            : String.join(addressParts, ', ');
    }


    // =========================================================
    // Main Wrapper
    // =========================================================

    public class AdminHomeData {
        @AuraEnabled public List<RecentlyViewedItem> recentlyViewed { get; set; }

        @AuraEnabled public List<AccountItem> accounts { get; set; }
        @AuraEnabled public List<ContactItem> contacts { get; set; }
        @AuraEnabled public List<AssetItem> assets { get; set; }

        @AuraEnabled public List<CaseItem> cases { get; set; }
        @AuraEnabled public List<WorkOrderItem> workOrders { get; set; }
        @AuraEnabled public List<MaintenanceLogItem> maintenanceLogs { get; set; }

        @AuraEnabled public List<PartCatalogItem> partCatalogs { get; set; }
        @AuraEnabled public List<WorkOrderPartItem> workOrderParts { get; set; }
        @AuraEnabled public List<ServiceManualItem> serviceManuals { get; set; }
    }


    // =========================================================
    // Recently Viewed Wrapper
    // =========================================================

    public class RecentlyViewedItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String objectLabel { get; set; }
        @AuraEnabled public Datetime lastViewedDate { get; set; }
    }


    // =========================================================
    // Customer Setup Wrappers
    // =========================================================

    public class AccountItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String billingAddress { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class ContactItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String mobile { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class AssetItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }


    // =========================================================
    // Service Operations Wrappers
    // =========================================================

    public class CaseItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class WorkOrderItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String displayStatus { get; set; }
        @AuraEnabled public Datetime scheduledVisit { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class MaintenanceLogItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String maintenanceNumber { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String outcome { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }


    // =========================================================
    // Parts & Knowledge Wrappers
    // =========================================================

    public class PartCatalogItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String compatibleModel { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class WorkOrderPartItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String partNumber { get; set; }
        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public String partCatalogName { get; set; }
        @AuraEnabled public Id machineId { get; set; }
        @AuraEnabled public String machineName { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }

    public class ServiceManualItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String documentType { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
    }
}