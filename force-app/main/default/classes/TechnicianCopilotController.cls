/**
 * TechnicianCopilotController
 *
 * Read-only data controller for the MillTrack Technician Copilot LWC.
 *
 * Responsibilities:
 * - Retrieve the primary Work Order.
 * - Retrieve the related Asset, Account, Contact, and Case.
 * - Retrieve recent Maintenance Logs.
 * - Retrieve sanitized similar-repair precedents from other customer assets.
 * - Retrieve related Work Order Parts.
 * - Return all information through LWC-friendly wrapper classes.
 *
 * Security:
 * - "with sharing" enforces record-level sharing for the primary Work Order context.
 * - Historical precedent retrieval intentionally uses SYSTEM_MODE for cross-customer
 *   service evidence, but only returns a sanitized technical DTO with no customer,
 *   account, contact, serial-number, Case-number, Asset-name, or record-ID details.
 * - Security.stripInaccessible removes fields the running user cannot read.
 * - Object accessibility is checked before querying an object.
 *
 * Notes:
 * - Dynamic field detection allows the controller to tolerate optional fields
 *   and minor API-name differences without failing compilation.
 * - No records are created or updated by this class.
 */
public with sharing class TechnicianCopilotController {

    private static final Integer DEFAULT_MAINTENANCE_LOG_LIMIT = 10;
    private static final Integer DEFAULT_PART_LIMIT = 50;
    private static final Integer DEFAULT_PRECEDENT_LIMIT = 3;
    private static final Integer PRECEDENT_CANDIDATE_LIMIT = 40;

    private static final Set<String> PRECEDENT_STOP_WORDS = new Set<String>{
        'a', 'an', 'and', 'are', 'as', 'at', 'be', 'been', 'being', 'by',
        'for', 'from', 'had', 'has', 'have', 'in', 'into', 'is', 'it', 'its',
        'of', 'on', 'or', 'that', 'the', 'then', 'this', 'to', 'was', 'were',
        'with', 'work', 'order', 'service', 'machine', 'asset', 'unit',
        'issue', 'problem', 'current', 'customer', 'technician', 'recommended',
        'recommendation', 'repair', 'inspect', 'verify', 'document'
    };

    /**
     * Main method called by the Technician Copilot LWC.
     *
     * @param workOrderId The Work Order record currently displayed.
     * @return CopilotResponse containing all available Work Order context.
     */
    @AuraEnabled(cacheable=true)
    public static CopilotResponse getCopilotContext(Id workOrderId) {
        validateWorkOrderId(workOrderId);

        CopilotResponse response = new CopilotResponse();
        response.workOrderId = workOrderId;

        SObject workOrderRecord = querySingleRecord('WorkOrder', workOrderId, getWorkOrderFields());

        if (workOrderRecord == null) {
            throw new AuraHandledException('The Work Order could not be found or you do not have access to it.');
        }

        response.workOrder = mapWorkOrder(workOrderRecord);

        Id assetId = getId(workOrderRecord, 'AssetId');
        Id accountId = getId(workOrderRecord, 'AccountId');
        Id contactId = getId(workOrderRecord, 'ContactId');
        Id caseId = getId(workOrderRecord, 'CaseId');
        Id ownerId = getId(workOrderRecord, 'OwnerId');
        Id assignedTechnicianId = getId(workOrderRecord, 'Suggested_Technician__c');
        Id serviceManagerId = getId(workOrderRecord, 'Service_Manager__c');

        
        //Related core records
        response.asset = mapAsset(querySingleRecord('Asset', assetId, getAssetFields()));
        response.account = mapAccount(querySingleRecord('Account', accountId, getAccountFields()));
        response.contact = mapContact(querySingleRecord('Contact', contactId, getContactFields()));
        response.caseRecord = mapCase(querySingleRecord('Case', caseId, getCaseFields()));

        // Sanitized cross-customer repair evidence for other assets of the same model.
        // The current Asset's own history remains in assetMaintenanceHistory.
        Id currentCustomerAccountId = response.asset != null && response.asset.accountId != null
            ? response.asset.accountId
            : accountId;

        response.similarRepairPrecedents = getSimilarRepairPrecedents(
            assetId,
            currentCustomerAccountId,
            response.asset,
            buildCurrentIssueText(response.workOrder, response.caseRecord),
            DEFAULT_PRECEDENT_LIMIT
        );

        //User display information
        Map<Id, UserInfo> userInfoById = queryUsers(new Set<Id>{ownerId, assignedTechnicianId, serviceManagerId});

        response.owner = userInfoById.get(ownerId);
        response.assignedTechnician = userInfoById.get(assignedTechnicianId);
        response.serviceManager = userInfoById.get(serviceManagerId);
 
        //Related service history and parts
        response.maintenanceLogs = getMaintenanceLogs(workOrderId, DEFAULT_MAINTENANCE_LOG_LIMIT);
        response.assetMaintenanceHistory = getAssetMaintenanceHistory(assetId, workOrderId, DEFAULT_MAINTENANCE_LOG_LIMIT);
        response.workOrderParts = getWorkOrderParts(workOrderId, DEFAULT_PART_LIMIT);
        response.summary = buildSummary(response);

        return response;
    }



    /*
     * ============================================================
     * VALIDATION
     * ============================================================
     */
    private static void validateWorkOrderId(Id workOrderId) {
        if (workOrderId == null) {
            throw new AuraHandledException('A Work Order ID is required.');
        }

        if (workOrderId.getSObjectType() != WorkOrder.SObjectType) {
            throw new AuraHandledException('The supplied record ID is not a Work Order.');
        }
    }


    /*
     * ============================================================
     * WORK ORDER
     * ============================================================
     */
    private static List<String> getWorkOrderFields() {
        return new List<String>{
            'Id',
            'WorkOrderNumber',
            'Subject',
            'Description',
            'Priority',
            'Status',
            'OwnerId',
            'AccountId',
            'ContactId',
            'CaseId',
            'AssetId',
            'CreatedDate',
            'LastModifiedDate',

            //custom fields
            'Dispatch_Status__c',
            'Resolution_Status__c',
            'AI_Dispatch_Summary__c',
            'Dispatch_Response__c',
            'Problem_Summary__c',
            'Recommended_Solution__c',
            'Recommended_Parts__c',
            'Previous_Failure__c',
            'Technician_Notes__c',
            'Labor_Hours__c',
            'Work_Started_Date_Time__c',
            'Work_Ended_Date_Time__c',
            'StartDate',
            'EndDate',
            'Suggested_Technician__c',
            'Service_Manager__c',
            'Recommended_Tools__c',
            'Recommended_Fix_Summary__c'
        };
    }

    private static WorkOrderInfo mapWorkOrder(SObject record) {
        if (record == null) {
            return null;
        }

        WorkOrderInfo info = new WorkOrderInfo();

        info.id = getId(record, 'Id');
        info.workOrderNumber = getString(record, 'WorkOrderNumber');
        info.subject = getString(record, 'Subject');
        info.description = getString(record, 'Description');
        info.priority = getString(record, 'Priority');
        info.standardStatus = getString(record, 'Status');
        info.dispatchStatus = getString(record, 'Dispatch_Status__c');
        info.resolutionStatus = getString(record, 'Resolution_Status__c');
        
        info.recommendedFixSummary = getString(record, 'Recommended_Fix_Summary__c');
        info.aiDispatchSummary = getString(record, 'AI_Dispatch_Summary__c');
        info.dispatchResponse = getString(record, 'Dispatch_Response__c');
        info.problemSummary = getString(record, 'Problem_Summary__c');
        info.recommendedSolution = getString(record, 'Recommended_Solution__c');
        info.recommendedParts = getString(record, 'Recommended_Parts__c');
        info.recommendedTools = getString(record, 'Recommended_Tools__c');
        info.previousFailure = getBoolean(record, 'Previous_Failure__c');
        info.technicianNotes = getString(record, 'Technician_Notes__c');
        info.laborHours = getDecimal(record, 'Labor_Hours__c');
        info.workStartedDateTime = firstNonNullDateTime(
            getDateTime(record, 'Work_Started_Date_Time__c'),
            getDateTime(record, 'StartDate')
        );
        info.workEndedDateTime = getDateTime(record, 'Work_Ended_Date_Time__c');
        info.endDateTime = getDateTime(record, 'EndDate');
        info.ownerId = getId(record, 'OwnerId');
        info.assignedTechnicianId = getId(record, 'Suggested_Technician__c');
        info.serviceManagerId = getId(record, 'Service_Manager__c');

        info.accountId = getId(record, 'AccountId');
        info.contactId = getId(record, 'ContactId');
        info.caseId = getId(record, 'CaseId');
        info.assetId = getId(record, 'AssetId');

        info.createdDate = getDateTime(record, 'CreatedDate');
        info.lastModifiedDate = getDateTime(record, 'LastModifiedDate');

        return info;
    }


    /*
     * ============================================================
     * ASSET / MACHINE
     * ============================================================
     */
    private static List<String> getAssetFields() {
        return new List<String>{
            'Id',
            'Name',
            'Status',
            'Description',
            'AccountId',
            'ContactId',
            'Product2Id',
            'InstallDate',
            'PurchaseDate',

            // Possible MillTrack machine fields
            'Serial_Number__c',
            'Manufacturer__c',
            'Model__c',
            'Machine_Status__c',
            'Warranty_Start_Date__c',
            'Warranty_End_Date__c',
            'Last_Service_Date__c'
        };
    }

    private static AssetInfo mapAsset(SObject record) {
        if (record == null) {
            return null;
        }

        AssetInfo info = new AssetInfo();

        info.id = getId(record, 'Id');
        info.name = getString(record, 'Name');
        info.standardStatus = getString(record, 'Status');
        info.machineStatus = getString(record, 'Machine_Status__c');
        info.description = getString(record, 'Description');

        info.serialNumber = getString(record, 'Serial_Number__c');
        info.manufacturer = getString(record, 'Manufacturer__c');
        info.model = getString(record, 'Model__c');

        info.installDate = getDate(record, 'InstallDate');
        info.purchaseDate = getDate(record, 'PurchaseDate');
        info.warrantyStartDate = getDate(record, 'Warranty_Start_Date__c');
        info.warrantyEndDate = getDate(record, 'Warranty_End_Date__c');
        info.lastServiceDate = getDate(record, 'Last_Service_Date__c');

        info.accountId = getId(record, 'AccountId');
        info.contactId = getId(record, 'ContactId');
        info.productId = getId(record, 'Product2Id');

        return info;
    }


    /*
     * ============================================================
     * ASSET / MACHINE History
     * ============================================================
     */
    private static List<MaintenanceLogInfo> getAssetMaintenanceHistory(Id assetId, Id currentWorkOrderId, Integer recordLimit) {
        List<MaintenanceLogInfo> results = new List<MaintenanceLogInfo>();

        String objectApiName = 'Maintenance_Log__c';

        if (assetId == null || !isObjectAccessible(objectApiName) || !fieldExists(objectApiName, 'Asset__c')) {
            return results;
        }

        List<String> requestedFields = new List<String>{
            'Id',
            'Name',
            'Asset__c',
            'Work_Order__c',
            'Maintenance_Date__c',
            'Maintenance_Type__c',
            'Performed_By__c',
            'Summary__c',
            'Root_Cause__c',
            'Technician_Notes__c',
            'Parts_Used__c',
            'Labor_Hours__c',
            'Issue_Resolved__c',
            'Follow_Up_Required__c',
            'CreatedDate',
            'LastModifiedDate'
        };

        List<String> fields = getExistingFields(objectApiName, requestedFields);

        if (fields.isEmpty()) {
            return results;
        }

        String queryString = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectApiName + ' WHERE Asset__c = :assetId';

        if (currentWorkOrderId != null && fieldExists(objectApiName, 'Work_Order__c')) {
            queryString += ' AND Work_Order__c != :currentWorkOrderId';
        }

        if (fieldExists(objectApiName, 'Maintenance_Date__c')) {
            queryString += ' ORDER BY Maintenance_Date__c DESC, CreatedDate DESC';
        } else {
            queryString += ' ORDER BY CreatedDate DESC';
        }

        queryString += ' LIMIT :recordLimit';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        Set<Id> performedByIds = new Set<Id>();

        for (SObject record : records) {
            performedByIds.add(getId(record, 'Performed_By__c'));
        }

        Map<Id, UserInfo> usersById = queryUsers(performedByIds);

        for (SObject record : records) {
            MaintenanceLogInfo info = new MaintenanceLogInfo();

            info.id = getId(record, 'Id');

            info.name = getString(record, 'Name');

            info.assetId = getId(record, 'Asset__c');

            info.workOrderId = getId(record, 'Work_Order__c');

            info.maintenanceDate = getDate(record, 'Maintenance_Date__c');

            info.maintenanceType = getString(record, 'Maintenance_Type__c');

            info.performedById = getId(record, 'Performed_By__c');

            info.performedBy = usersById.get(info.performedById);

            info.summary = getString(record, 'Summary__c');

            info.rootCause = getString(record, 'Root_Cause__c');

            info.technicianNotes = getString(record, 'Technician_Notes__c');

            info.partsUsed = getString(record, 'Parts_Used__c');

            info.laborHours = getDecimal(record, 'Labor_Hours__c');

            info.issueResolved = getBoolean(record, 'Issue_Resolved__c');

            info.followUpRequired = getBoolean(record, 'Follow_Up_Required__c');

            info.createdDate = getDateTime(record, 'CreatedDate');

            info.lastModifiedDate = getDateTime(record, 'LastModifiedDate');

            results.add(info);
        }

        return results;
    }


    /*
     * ============================================================
     * SIMILAR REPAIR PRECEDENTS
     * ============================================================
     *
     * Purpose:
     * - Service History remains exact-Asset history only.
     * - Similar Repair Precedents are successful repairs from DIFFERENT
     *   Assets owned by DIFFERENT customer Accounts.
     * - Candidates must use the same machine model (and manufacturer when
     *   available) and must share meaningful issue terms with the current
     *   Work Order / Case.
     *
     * Privacy:
     * - Historical records are queried in SYSTEM_MODE so the technician can
     *   benefit from enterprise repair knowledge even when record sharing
     *   would hide another customer's completed Work Order.
     * - The returned wrapper intentionally contains ONLY technical evidence:
     *   manufacturer/model, problem summary, manager recommended fix,
     *   technician repair notes, maintenance date, and resolved outcome.
     * - No Account, Contact, customer name, serial number, Case number,
     *   Asset name, Salesforce record ID, or historical Work Order number is
     *   exposed to the LWC.
     */
    private static List<SimilarRepairPrecedentInfo> getSimilarRepairPrecedents(
        Id currentAssetId,
        Id currentAccountId,
        AssetInfo currentAsset,
        String currentIssueText,
        Integer recordLimit
    ) {
        List<SimilarRepairPrecedentInfo> results = new List<SimilarRepairPrecedentInfo>();

        if (
            currentAssetId == null ||
            currentAccountId == null ||
            currentAsset == null ||
            String.isBlank(currentAsset.model) ||
            String.isBlank(currentIssueText) ||
            recordLimit == null ||
            recordLimit <= 0
        ) {
            return results;
        }

        String maintenanceObject = 'Maintenance_Log__c';

        if (
            !isObjectAccessible(maintenanceObject) ||
            !isObjectAccessible('Asset') ||
            !isObjectAccessible('WorkOrder') ||
            !fieldExists(maintenanceObject, 'Asset__c') ||
            !fieldExists(maintenanceObject, 'Work_Order__c') ||
            !fieldExists(maintenanceObject, 'Issue_Resolved__c') ||
            !fieldExists(maintenanceObject, 'Follow_Up_Required__c') ||
            !fieldExists(maintenanceObject, 'Maintenance_Type__c') ||
            !fieldExists('Asset', 'AccountId') ||
            !fieldExists('Asset', 'Model__c')
        ) {
            return results;
        }

        List<String> selectFields = getExistingFields(
            maintenanceObject,
            new List<String>{
                'Id',
                'Asset__c',
                'Work_Order__c',
                'Maintenance_Date__c',
                'Maintenance_Type__c',
                'Summary__c',
                'Root_Cause__c',
                'Technician_Notes__c',
                'Issue_Resolved__c',
                'Follow_Up_Required__c',
                'CreatedDate'
            }
        );

        // Historical Work Order fields used for relevance scoring and sanitized display.
        // Asset relationship fields are used only in WHERE filters below; they are
        // deliberately not selected or returned.
        if (fieldExists('WorkOrder', 'Subject')) {
            selectFields.add('Work_Order__r.Subject');
        }
        if (fieldExists('WorkOrder', 'Description')) {
            selectFields.add('Work_Order__r.Description');
        }
        if (fieldExists('WorkOrder', 'Problem_Summary__c')) {
            selectFields.add('Work_Order__r.Problem_Summary__c');
        }
        if (fieldExists('WorkOrder', 'Recommended_Fix_Summary__c')) {
            selectFields.add('Work_Order__r.Recommended_Fix_Summary__c');
        }
        if (selectFields.isEmpty()) {
            return results;
        }

        Map<String, Object> bindValues = new Map<String, Object>{
            'currentAssetId' => currentAssetId,
            'currentAccountId' => currentAccountId,
            'currentModel' => currentAsset.model
        };

        String queryString =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + maintenanceObject +
            ' WHERE Asset__c != :currentAssetId' +
            ' AND Asset__r.AccountId != null' +
            ' AND Asset__r.AccountId != :currentAccountId' +
            ' AND Asset__r.Model__c = :currentModel' +
            ' AND Work_Order__c != null' +
            ' AND Issue_Resolved__c = true' +
            ' AND Follow_Up_Required__c = false';

        if (
            !String.isBlank(currentAsset.manufacturer) &&
            fieldExists('Asset', 'Manufacturer__c')
        ) {
            queryString += ' AND Asset__r.Manufacturer__c = :currentManufacturer';
            bindValues.put('currentManufacturer', currentAsset.manufacturer);
        }

        if (fieldExists(maintenanceObject, 'Maintenance_Date__c')) {
            queryString += ' ORDER BY Maintenance_Date__c DESC, CreatedDate DESC';
        } else {
            queryString += ' ORDER BY CreatedDate DESC';
        }

        queryString += ' LIMIT ' + String.valueOf(PRECEDENT_CANDIDATE_LIMIT);

        List<SObject> records = Database.queryWithBinds(
            queryString,
            bindValues,
            AccessLevel.SYSTEM_MODE
        );

        records = stripUnreadableFields(records);

        List<PrecedentCandidate> rankedCandidates = new List<PrecedentCandidate>();

        for (SObject record : records) {
            SObject historicalWorkOrder = getRelatedRecord(record, 'Work_Order__r');

            if (historicalWorkOrder == null) {
                continue;
            }

            String maintenanceType = getString(record, 'Maintenance_Type__c');

            // Mirror MillTrack's Historical Repair Intelligence success rule:
            // use completed repair/emergency evidence and exclude temporary fixes.
            if (String.isBlank(maintenanceType)) {
                continue;
            }

            String normalizedMaintenanceType = maintenanceType.toLowerCase();
            Boolean isRepairEvidence =
                normalizedMaintenanceType.contains('repair') ||
                normalizedMaintenanceType.contains('emergency');
            Boolean isTemporary =
                normalizedMaintenanceType.contains('temporary') ||
                normalizedMaintenanceType.contains('temp fix');

            if (!isRepairEvidence || isTemporary) {
                continue;
            }

            String problemSummary = firstNonBlankString(
                getString(historicalWorkOrder, 'Problem_Summary__c'),
                getString(historicalWorkOrder, 'Description'),
                getString(record, 'Summary__c')
            );

            if (String.isBlank(problemSummary)) {
                continue;
            }

            String historicalIssueText = joinNonBlankStrings(
                new List<String>{
                    problemSummary,
                    getString(historicalWorkOrder, 'Subject'),
                    getString(historicalWorkOrder, 'Description'),
                    getString(record, 'Summary__c'),
                    getString(record, 'Root_Cause__c')
                }
            );

            Integer similarityScore = calculateSimilarityScore(
                currentIssueText,
                historicalIssueText
            );

            // Same model alone is not enough; require at least one meaningful
            // shared issue term so unrelated repairs are not shown as precedent.
            if (similarityScore <= 0) {
                continue;
            }

            String managerRecommendedFix = getString(
                historicalWorkOrder,
                'Recommended_Fix_Summary__c'
            );
            String technicianRepairNotes = getString(
                record,
                'Technician_Notes__c'
            );

            // A precedent card should contain the three pieces of evidence the
            // technician actually needs. Skip incomplete historical records.
            if (
                String.isBlank(managerRecommendedFix) ||
                String.isBlank(technicianRepairNotes)
            ) {
                continue;
            }

            SimilarRepairPrecedentInfo info = new SimilarRepairPrecedentInfo();
            info.manufacturer = currentAsset.manufacturer;
            info.model = currentAsset.model;
            info.problemSummary = problemSummary;
            info.recommendedFixSummary = managerRecommendedFix;
            info.technicianRepairNotes = technicianRepairNotes;
            info.maintenanceDate = getDate(record, 'Maintenance_Date__c');
            info.issueResolved = getBoolean(record, 'Issue_Resolved__c');

            PrecedentCandidate candidate = new PrecedentCandidate();
            candidate.score = similarityScore;
            candidate.sortDate = getDateTime(record, 'CreatedDate');
            candidate.info = info;

            rankedCandidates.add(candidate);
        }

        rankedCandidates.sort();

        Integer finalLimit = recordLimit < rankedCandidates.size()
            ? recordLimit
            : rankedCandidates.size();

        for (Integer i = 0; i < finalLimit; i++) {
            results.add(rankedCandidates[i].info);
        }

        return results;
    }

    private static String buildCurrentIssueText(
        WorkOrderInfo workOrder,
        CaseInfo caseRecord
    ) {
        List<String> parts = new List<String>();

        if (workOrder != null) {
            parts.add(workOrder.subject);
            parts.add(workOrder.problemSummary);
            parts.add(workOrder.description);
        }

        if (caseRecord != null) {
            parts.add(caseRecord.subject);
            parts.add(caseRecord.description);
        }

        return joinNonBlankStrings(parts);
    }

    private static Integer calculateSimilarityScore(
        String currentIssueText,
        String historicalIssueText
    ) {
        Set<String> currentTokens = toMeaningfulTokens(currentIssueText);
        Set<String> historicalTokens = toMeaningfulTokens(historicalIssueText);

        if (currentTokens.isEmpty() || historicalTokens.isEmpty()) {
            return 0;
        }

        Integer sharedTokenCount = 0;

        for (String token : currentTokens) {
            if (historicalTokens.contains(token)) {
                sharedTokenCount++;
            }
        }

        if (sharedTokenCount == 0) {
            return 0;
        }

        // Shared technical terms are the primary relevance signal.
        // Give stronger matches a modest bonus without pretending this is a
        // diagnostic confidence score.
        Integer score = sharedTokenCount * 10;

        if (sharedTokenCount >= 2) {
            score += 5;
        }
        if (sharedTokenCount >= 3) {
            score += 5;
        }

        return score;
    }

    private static Set<String> toMeaningfulTokens(String text) {
        Set<String> results = new Set<String>();

        if (String.isBlank(text)) {
            return results;
        }

        String normalized = text
            .toLowerCase()
            .replaceAll('[^a-z0-9]+', ' ')
            .trim();

        if (String.isBlank(normalized)) {
            return results;
        }

        for (String token : normalized.split('\\s+')) {
            if (String.isBlank(token)) {
                continue;
            }

            Boolean containsDigit = token.replaceAll('[^0-9]', '').length() > 0;

            if (token.length() < 3 && !containsDigit) {
                continue;
            }

            if (PRECEDENT_STOP_WORDS.contains(token)) {
                continue;
            }

            results.add(token);
        }

        return results;
    }

    private static String joinNonBlankStrings(List<String> values) {
        List<String> cleanedValues = new List<String>();

        if (values == null) {
            return '';
        }

        for (String value : values) {
            if (!String.isBlank(value)) {
                cleanedValues.add(value.trim());
            }
        }

        return String.join(cleanedValues, ' ');
    }

    private static String firstNonBlankString(
        String firstValue,
        String secondValue,
        String thirdValue
    ) {
        if (!String.isBlank(firstValue)) {
            return firstValue;
        }
        if (!String.isBlank(secondValue)) {
            return secondValue;
        }
        return thirdValue;
    }

    private static String firstNonBlankString(
        String firstValue,
        String secondValue
    ) {
        return firstNonBlankString(firstValue, secondValue, null);
    }

    private static SObject getRelatedRecord(
        SObject record,
        String relationshipName
    ) {
        if (record == null || String.isBlank(relationshipName)) {
            return null;
        }

        try {
            return record.getSObject(relationshipName);
        } catch (Exception ex) {
            return null;
        }
    }


    /*
     * ============================================================
     * ACCOUNT
     * ============================================================
     */
    private static List<String> getAccountFields() {
        return new List<String>{
            'Id',
            'Name',
            'Phone',
            'Website',
            'BillingStreet',
            'BillingCity',
            'BillingState',
            'BillingPostalCode',
            'BillingCountry'
        };
    }

    private static AccountInfo mapAccount(SObject record) {
        if (record == null) {
            return null;
        }

        AccountInfo info = new AccountInfo();

        info.id = getId(record, 'Id');
        info.name = getString(record, 'Name');
        info.phone = getString(record, 'Phone');
        info.website = getString(record, 'Website');
        info.billingStreet = getString(record, 'BillingStreet');
        info.billingCity = getString(record, 'BillingCity');
        info.billingState = getString(record, 'BillingState');
        info.billingPostalCode = getString(record, 'BillingPostalCode');
        info.billingCountry = getString(record, 'BillingCountry');

        return info;
    }


    /*
     * ============================================================
     * CONTACT
     * ============================================================
     */
    private static List<String> getContactFields() {
        return new List<String>{
            'Id',
            'Name',
            'FirstName',
            'LastName',
            'Email',
            'Phone',
            'Title',
            'AccountId'
        };
    }

    private static ContactInfo mapContact(SObject record) {
        if (record == null) {
            return null;
        }

        ContactInfo info = new ContactInfo();

        info.id = getId(record, 'Id');
        info.name = getString(record, 'Name');
        info.firstName = getString(record, 'FirstName');
        info.lastName = getString(record, 'LastName');
        info.email = getString(record, 'Email');
        info.phone = getString(record, 'Phone');
        info.title = getString(record, 'Title');
        info.accountId = getId(record, 'AccountId');

        return info;
    }


    /*
     * ============================================================
     * CASE
     * ============================================================
     */
    private static List<String> getCaseFields() {
        return new List<String>{
            'Id',
            'CaseNumber',
            'Subject',
            'Description',
            'Priority',
            'Status',
            'Origin',
            'OwnerId',
            'AccountId',
            'ContactId',
            'AssetId',
            'CreatedDate',
            'ClosedDate'
        };
    }

    private static CaseInfo mapCase(SObject record) {
        if (record == null) {
            return null;
        }

        CaseInfo info = new CaseInfo();

        info.id = getId(record, 'Id');
        info.caseNumber = getString(record, 'CaseNumber');
        info.subject = getString(record, 'Subject');
        info.description = getString(record, 'Description');
        info.priority = getString(record, 'Priority');
        info.status = getString(record, 'Status');
        info.origin = getString(record, 'Origin');

        info.ownerId = getId(record, 'OwnerId');
        info.accountId = getId(record, 'AccountId');
        info.contactId = getId(record, 'ContactId');
        info.assetId = getId(record, 'AssetId');

        info.createdDate = getDateTime(record, 'CreatedDate');
        info.closedDate = getDateTime(record, 'ClosedDate');

        return info;
    }


    /*
     * ============================================================
     * USERS
     * ============================================================
     */
    private static Map<Id, UserInfo> queryUsers(Set<Id> userIds) {
        Map<Id, UserInfo> results = new Map<Id, UserInfo>();

        userIds.remove(null);

        if (userIds.isEmpty()) {
            return results;
        }

        if (!isObjectAccessible('User')) {
            return results;
        }

        List<String> fields = getExistingFields('User', new List<String>{
            'Id',
            'Name',
            'Email',
            'Phone',
            'MobilePhone',
            'Title',
            'SmallPhotoUrl'
        });

        if (fields.isEmpty()) {
            return results;
        }

        String queryString = 'SELECT ' + String.join(fields, ', ') + ' FROM User' + ' WHERE Id IN :userIds';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        for (SObject record : records) {
            UserInfo info = new UserInfo();

            info.id = getId(record, 'Id');
            info.name = getString(record, 'Name');
            info.email = getString(record, 'Email');
            info.phone = getString(record, 'Phone');
            info.mobilePhone = getString(record, 'MobilePhone');
            info.title = getString(record, 'Title');
            info.photoUrl = getString(record, 'SmallPhotoUrl');

            results.put(info.id, info);
        }

        return results;
    }


    /*
     * ============================================================
     * MAINTENANCE LOGS
     * ============================================================
     */
    private static List<MaintenanceLogInfo> getMaintenanceLogs(Id workOrderId, Integer recordLimit) {
        List<MaintenanceLogInfo> results = new List<MaintenanceLogInfo>();

        String objectApiName = 'Maintenance_Log__c';

        if (!isObjectAccessible(objectApiName)) {
            return results;
        }

        List<String> requestedFields = new List<String>{
            'Id',
            'Name',
            'Asset__c',
            'Work_Order__c',
            'Maintenance_Date__c',
            'Maintenance_Type__c',
            'Performed_By__c',
            'Summary__c',
            'Root_Cause__c',
            'Technician_Notes__c',
            'Parts_Used__c',
            'Labor_Hours__c',
            'Issue_Resolved__c',
            'Follow_Up_Required__c',
            'CreatedDate',
            'LastModifiedDate'
        };

        List<String> fields = getExistingFields(objectApiName, requestedFields);

        if (fields.isEmpty() || !fieldExists(objectApiName, 'Work_Order__c')) {
            return results;
        }

        String queryString = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectApiName + ' WHERE Work_Order__c = :workOrderId';

        if (fieldExists(objectApiName, 'Maintenance_Date__c')) {
            queryString += ' ORDER BY Maintenance_Date__c DESC';
        } else {
            queryString += ' ORDER BY CreatedDate DESC';
        }

        queryString += ' LIMIT :recordLimit';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        Set<Id> performedByIds = new Set<Id>();

        for (SObject record : records) {
            performedByIds.add(getId(record, 'Performed_By__c'));
        }

        Map<Id, UserInfo> userInfoById = queryUsers(performedByIds);

        for (SObject record : records) {
            MaintenanceLogInfo info = new MaintenanceLogInfo();

            info.id = getId(record, 'Id');
            info.name = getString(record, 'Name');
            info.assetId = getId(record, 'Asset__c');
            info.workOrderId = getId(record, 'Work_Order__c');
            info.maintenanceDate = getDate(record, 'Maintenance_Date__c');
            info.maintenanceType = getString(record, 'Maintenance_Type__c');
            info.performedById = getId(record, 'Performed_By__c');
            info.performedBy = userInfoById.get(info.performedById);
            info.summary = getString(record, 'Summary__c');
            info.rootCause = getString(record, 'Root_Cause__c');
            info.technicianNotes = getString(record, 'Technician_Notes__c');
            info.partsUsed = getString(record, 'Parts_Used__c');
            info.laborHours = getDecimal(record, 'Labor_Hours__c');
            info.issueResolved = getBoolean(record, 'Issue_Resolved__c');
            info.followUpRequired = getBoolean(record, 'Follow_Up_Required__c');
            info.createdDate = getDateTime(record, 'CreatedDate');
            info.lastModifiedDate = getDateTime(record, 'LastModifiedDate');

            results.add(info);
        }

        return results;
    }


    /*
     * ============================================================
     * WORK ORDER PARTS
     * ============================================================
     */
    private static List<WorkOrderPartInfo> getWorkOrderParts(Id workOrderId, Integer recordLimit) {
        List<WorkOrderPartInfo> results = new List<WorkOrderPartInfo>();

        String objectApiName = 'Work_Order_Part__c';

        if (!isObjectAccessible(objectApiName)) {
            return results;
        }

        List<String> requestedFields = new List<String>{
            'Id',
            'Name',
            'Work_Order__c',
            'Part_Catalog__c',
            'Quantity__c',
            'Quantity_Needed__c',
            'Order_Status__c',
            'Ordered_By__c',
            'Supplier_Name__c',
            'Supplier_Phone__c',
            'Order_URL__c',
            'CreatedDate',
            'LastModifiedDate',
            'Quantity_Used__c',
            'Notes__c',
            'Machine__c'
        };

        List<String> fields = getExistingFields(objectApiName, requestedFields);

        if (fields.isEmpty() || !fieldExists(objectApiName, 'Work_Order__c')) {
            return results;
        }

        String queryString =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE Work_Order__c = :workOrderId' +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :recordLimit';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        Set<Id> catalogIds = new Set<Id>();
        Set<Id> orderedByIds = new Set<Id>();

        for (SObject record : records) {
            catalogIds.add(getId(record, 'Part_Catalog__c'));
            orderedByIds.add(getId(record, 'Ordered_By__c'));
        }

        Map<Id, String> catalogNames = queryNamesById('Part_Catalog__c', catalogIds);
        Map<Id, UserInfo> orderedByUsers = queryUsers(orderedByIds);

        for (SObject record : records) {
            WorkOrderPartInfo info = new WorkOrderPartInfo();

            info.id = getId(record, 'Id');
            info.name = getString(record, 'Name');
            info.workOrderId = getId(record, 'Work_Order__c');
            info.partCatalogId = getId(record, 'Part_Catalog__c');
            info.partName = catalogNames.get(info.partCatalogId);
            info.quantity = firstNonNullDecimal(
                getDecimal(record, 'Quantity_Needed__c'),
                getDecimal(record, 'Quantity__c')
            );
            info.quantityUsed = getDecimal(record, 'Quantity_Used__c');
            info.orderStatus = getString(record, 'Order_Status__c');
            info.orderedById = getId(record, 'Ordered_By__c');
            info.orderedBy = orderedByUsers.get(info.orderedById);
            info.supplierName = getString(record, 'Supplier_Name__c');
            info.supplierPhone = getString(record, 'Supplier_Phone__c');
            info.orderUrl = getString(record, 'Order_URL__c');
            info.createdDate = getDateTime(record, 'CreatedDate');
            info.lastModifiedDate = getDateTime(record, 'LastModifiedDate');
            info.notes = getString(record, 'Notes__c');
            info.machineId = getId(record, 'Machine__c');
            

            results.add(info);
        }

        return results;
    }


    /*
     * ============================================================
     * SUMMARY
     * ============================================================
     */
    private static CopilotSummary buildSummary(CopilotResponse response) {
        CopilotSummary summary = new CopilotSummary();

        summary.hasWorkOrder = response.workOrder != null;
        summary.hasAsset = response.asset != null;
        summary.hasCustomer = response.account != null || response.contact != null;
        summary.hasCase = response.caseRecord != null;
        summary.maintenanceLogCount = response.maintenanceLogs == null ? 0 : response.maintenanceLogs.size();
        summary.partCount = response.workOrderParts == null ? 0 : response.workOrderParts.size();
        summary.hasCurrentWorkOrderActivity = summary.maintenanceLogCount > 0;
        summary.hasParts = summary.partCount > 0;
        summary.hasAiDiagnosis = response.workOrder != null &&
            (
                !String.isBlank(response.workOrder.aiDispatchSummary) ||
                !String.isBlank(response.workOrder.problemSummary) ||
                !String.isBlank(response.workOrder.recommendedSolution)
            );
        summary.hasIssueSummary = response.workOrder != null && !String.isBlank(response.workOrder.problemSummary);
        summary.hasRecommendedSolution = response.workOrder != null && !String.isBlank(response.workOrder.recommendedSolution);
        summary.hasRecommendedTools = response.workOrder != null && !String.isBlank(response.workOrder.recommendedTools);
        summary.assetMaintenanceHistoryCount = response.assetMaintenanceHistory == null ? 0 : response.assetMaintenanceHistory.size();
        summary.hasAssetMaintenanceHistory = summary.assetMaintenanceHistoryCount > 0;
        summary.similarRepairPrecedentCount = response.similarRepairPrecedents == null
            ? 0
            : response.similarRepairPrecedents.size();
        summary.hasSimilarRepairPrecedents = summary.similarRepairPrecedentCount > 0;
        summary.hasRecommendedFixSummary = response.workOrder != null &&
            String.isNotBlank(response.workOrder.recommendedFixSummary);

        return summary;
    }


    /*
     * ============================================================
     * GENERIC QUERY HELPERS
     * ============================================================
     */
    private static SObject querySingleRecord(String objectApiName, Id recordId, List<String> requestedFields) {
        if (recordId == null || !isObjectAccessible(objectApiName)) {
            return null;
        }

        List<String> fields = getExistingFields(objectApiName, requestedFields);

        if (fields.isEmpty()) {
            return null;
        }

        String queryString =
            'SELECT ' + String.join(fields, ', ') +
            ' FROM ' + objectApiName +
            ' WHERE Id = :recordId' +
            ' LIMIT 1';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        return records.isEmpty() ? null : records[0];
    }

    private static Map<Id, String> queryNamesById(String objectApiName, Set<Id> recordIds) {
        Map<Id, String> results = new Map<Id, String>();

        recordIds.remove(null);

        if (recordIds.isEmpty() || !isObjectAccessible(objectApiName) || !fieldExists(objectApiName, 'Name')) {
            return results;
        }

        String queryString =
            'SELECT Id, Name' +
            ' FROM ' + objectApiName +
            ' WHERE Id IN :recordIds';

        List<SObject> records = Database.query(queryString);
        records = stripUnreadableFields(records);

        for (SObject record : records) {
            results.put(getId(record, 'Id'), getString(record, 'Name'));
        }

        return results;
    }

    private static List<SObject> stripUnreadableFields(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return records;
        }

        return Security.stripInaccessible(AccessType.READABLE, records).getRecords();
    }


    /*
     * ============================================================
     * SCHEMA HELPERS
     * ============================================================
     */
    private static Boolean isObjectAccessible(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);

        return objectType != null && objectType.getDescribe().isAccessible();
    }

    private static Boolean fieldExists(String objectApiName, String fieldApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);

        if (objectType == null) {
            return false;
        }

        return objectType
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }

    private static List<String> getExistingFields(String objectApiName, List<String> requestedFields) {
        List<String> existingFields = new List<String>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);

        if (objectType == null) {
            return existingFields;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String fieldName : requestedFields) {
            if (fieldMap.containsKey(fieldName)) {
                existingFields.add(fieldName);
            }
        }

        return existingFields;
    }


    /*
     * ============================================================
     * SAFE VALUE HELPERS
     * ============================================================
     */
    private static Object getValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName) ||
            !record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)
            ) {
            return null;
        }

        return record.get(fieldApiName);
    }

    private static String getString(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static Id getId(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : (Id) value;
    }

    private static Decimal getDecimal(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : (Decimal) value;
    }

    private static Boolean getBoolean(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : (Boolean) value;
    }

    private static Date getDate(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : (Date) value;
    }

    private static Datetime getDateTime(SObject record, String fieldApiName) {
        Object value = getValue(record, fieldApiName);
        return value == null ? null : (Datetime) value;
    }

    private static Decimal firstNonNullDecimal(Decimal firstValue, Decimal secondValue) {
        return firstValue != null ? firstValue : secondValue;
    }

    private static Datetime firstNonNullDateTime(Datetime firstValue, Datetime secondValue) {
        return firstValue != null ? firstValue : secondValue;
    }


    /*
     * ============================================================
     * RESPONSE WRAPPERS
     * ============================================================
     */
    public class CopilotResponse {
        @AuraEnabled public Id workOrderId {get; set;}

        @AuraEnabled public WorkOrderInfo workOrder {get; set;}
        @AuraEnabled public AssetInfo asset {get; set;}
        @AuraEnabled public AccountInfo account {get; set;}
        @AuraEnabled public ContactInfo contact {get; set;}
        @AuraEnabled public CaseInfo caseRecord {get; set;}
        @AuraEnabled public UserInfo owner {get; set;}
        @AuraEnabled public UserInfo assignedTechnician {get; set;}
        @AuraEnabled public UserInfo serviceManager {get; set;}
        @AuraEnabled public List<MaintenanceLogInfo> maintenanceLogs {get; set;}
        @AuraEnabled public List<MaintenanceLogInfo> assetMaintenanceHistory { get; set; }
        @AuraEnabled public List<SimilarRepairPrecedentInfo> similarRepairPrecedents { get; set; }
        @AuraEnabled public List<WorkOrderPartInfo> workOrderParts {get; set;}

        @AuraEnabled public CopilotSummary summary {get; set;}
    }

    public class WorkOrderInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workOrderNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String standardStatus { get; set; }
        @AuraEnabled public String dispatchStatus { get; set; }
        @AuraEnabled public String resolutionStatus { get; set; }

        @AuraEnabled public String aiDispatchSummary { get; set; }
        @AuraEnabled public String dispatchResponse { get; set; }
        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }
        @AuraEnabled public String recommendedSolution { get; set; }
        @AuraEnabled public String recommendedParts { get; set; }
        @AuraEnabled public String recommendedTools { get; set; }
        @AuraEnabled public Boolean previousFailure { get; set; }
        @AuraEnabled public String technicianNotes { get; set; }

        @AuraEnabled public Decimal laborHours { get; set; }
        @AuraEnabled public Datetime workStartedDateTime { get; set; }
        @AuraEnabled public Datetime workEndedDateTime { get; set; }
        @AuraEnabled public Datetime endDateTime { get; set; }

        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public Id assignedTechnicianId { get; set; }
        @AuraEnabled public Id serviceManagerId { get; set; }

        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id caseId { get; set; }
        @AuraEnabled public Id assetId { get; set; }

        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }

    public class AssetInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String serialNumber { get; set; }
        @AuraEnabled public String standardStatus { get; set; }
        @AuraEnabled public String machineStatus { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }

        @AuraEnabled public Date installDate { get; set; }
        @AuraEnabled public Date purchaseDate { get; set; }
        @AuraEnabled public Date warrantyStartDate { get; set; }
        @AuraEnabled public Date warrantyEndDate { get; set; }
        @AuraEnabled public Date lastServiceDate { get; set; }

        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id productId { get; set; }
    }

    public class AccountInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String website { get; set; }
        @AuraEnabled public String billingStreet { get; set; }
        @AuraEnabled public String billingCity { get; set; }
        @AuraEnabled public String billingState { get; set; }
        @AuraEnabled public String billingPostalCode { get; set; }
        @AuraEnabled public String billingCountry { get; set; }
    }

    public class ContactInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public Id accountId { get; set; }
    }

    public class CaseInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String origin { get; set; }

        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id assetId { get; set; }

        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime closedDate { get; set; }
    }

    public class UserInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String mobilePhone { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String photoUrl { get; set; }
    }

    public class MaintenanceLogInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Id assetId { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }

        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public String maintenanceType { get; set; }

        @AuraEnabled public Id performedById { get; set; }
        @AuraEnabled public UserInfo performedBy { get; set; }

        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public String rootCause { get; set; }
        @AuraEnabled public String technicianNotes { get; set; }
        @AuraEnabled public String partsUsed { get; set; }
        @AuraEnabled public Decimal laborHours { get; set; }

        @AuraEnabled public Boolean issueResolved { get; set; }
        @AuraEnabled public Boolean followUpRequired { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }


    public class SimilarRepairPrecedentInfo {
        @AuraEnabled public String manufacturer { get; set; }
        @AuraEnabled public String model { get; set; }
        @AuraEnabled public String problemSummary { get; set; }
        @AuraEnabled public String recommendedFixSummary { get; set; }
        @AuraEnabled public String technicianRepairNotes { get; set; }
        @AuraEnabled public Date maintenanceDate { get; set; }
        @AuraEnabled public Boolean issueResolved { get; set; }
    }

    private class PrecedentCandidate implements Comparable {
        public Integer score { get; set; }
        public Datetime sortDate { get; set; }
        public SimilarRepairPrecedentInfo info { get; set; }

        public Integer compareTo(Object otherObject) {
            PrecedentCandidate other = (PrecedentCandidate) otherObject;

            Integer thisScore = score == null ? 0 : score;
            Integer otherScore = other == null || other.score == null ? 0 : other.score;

            if (thisScore != otherScore) {
                return thisScore > otherScore ? -1 : 1;
            }

            Long thisTime = 0;
            Long otherTime = 0;

            if (sortDate != null) {
                thisTime = sortDate.getTime();
            }

            if (other != null && other.sortDate != null) {
                otherTime = other.sortDate.getTime();
            }

            if (thisTime == otherTime) {
                return 0;
            }

            return thisTime > otherTime ? -1 : 1;
        }
    }

    public class WorkOrderPartInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Id workOrderId { get; set; }

        @AuraEnabled public Id partCatalogId { get; set; }
        @AuraEnabled public String partName { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public String orderStatus { get; set; }

        @AuraEnabled public Id orderedById { get; set; }
        @AuraEnabled public UserInfo orderedBy { get; set; }

        @AuraEnabled public String supplierName { get; set; }
        @AuraEnabled public String supplierPhone { get; set; }
        @AuraEnabled public String orderUrl { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public Decimal quantityUsed { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public Id machineId { get; set; }
    }

    public class CopilotSummary {
        @AuraEnabled public Boolean hasWorkOrder { get; set; }
        @AuraEnabled public Boolean hasAsset { get; set; }
        @AuraEnabled public Boolean hasCustomer { get; set; }
        @AuraEnabled public Boolean hasCase { get; set; }
        @AuraEnabled public Boolean hasAiDiagnosis { get; set; }
        @AuraEnabled public Boolean hasCurrentWorkOrderActivity {get; set;}
        @AuraEnabled public Boolean hasParts { get; set; }
        @AuraEnabled public Integer maintenanceLogCount {get; set;}
        @AuraEnabled public Integer partCount { get; set; }
        @AuraEnabled public Boolean hasIssueSummary { get; set; }
        @AuraEnabled public Boolean hasRecommendedSolution { get; set; }
        @AuraEnabled public Boolean hasRecommendedTools { get; set; }
        @AuraEnabled public Boolean hasAssetMaintenanceHistory { get; set; }
        @AuraEnabled public Integer assetMaintenanceHistoryCount { get; set; }
        @AuraEnabled public Boolean hasSimilarRepairPrecedents { get; set; }
        @AuraEnabled public Integer similarRepairPrecedentCount { get; set; }
        @AuraEnabled public Boolean hasRecommendedFixSummary { get; set; }
    }
}