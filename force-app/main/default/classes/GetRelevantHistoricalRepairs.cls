public with sharing class GetRelevantHistoricalRepairs {

    private static final Integer DEFAULT_MAX_RESULTS = 3;
    private static final Integer MAX_RESULTS_ALLOWED = 5;
    private static final Integer CANDIDATE_LIMIT = 30;

    /*
     * Common words that should not make two repair records appear related.
     * Historical Repair Intelligence v1 intentionally uses lightweight, deterministic lexical matching rather than semantic/vector search.
     */
    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'and', 'for', 'with', 'this', 'that', 'from', 'into',
        'onto', 'when', 'then', 'than', 'have', 'has', 'had', 'was',
        'were', 'are', 'is', 'been', 'being', 'can', 'could', 'should',
        'would', 'will', 'may', 'might', 'not', 'but', 'about', 'after',
        'before', 'during', 'while',

        // General equipment/service words.
        'machine', 'mill', 'milling', 'issue', 'problem', 'repair',
        'service', 'customer', 'technician', 'work', 'order',
        'model', 'unit', 'equipment',

        // Generic repair verbs that do not establish problem similarity.
        'replace', 'replaced', 'replacing', 'replacement',
        'repairing', 'repaired',
        'fix', 'fixed', 'fixing',
        'install', 'installed', 'installing',
        'remove', 'removed',
        'performed', 'completed',

        // Common filler / contraction tokens.
        'isnt', 'doesnt', 'didnt', 'wont', 'cant'
    };

    public class Request {
        @InvocableVariable(
            required=true
            label='Current Work Order ID'
            description='Salesforce Work Order ID for the technician’s current repair.'
        )
        public Id workOrderId;

        @InvocableVariable(
            label='Technician Question or Observation'
            description='The technician’s current question, symptom, observation, or troubleshooting context.'
        )
        public String technicianQuery;

        @InvocableVariable(
            label='Maximum Results'
            description='Maximum number of historical repair precedents to return. Defaults to 3 and cannot exceed 5.'
        )
        public Integer maxResults;
    }

    public class Result {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String statusCode;

        @InvocableVariable
        public String statusMessage;

        @InvocableVariable
        public Integer matchCount;

        @InvocableVariable
        public String historicalRepairContext;
    }

    private class ScoredRepair implements Comparable {
        public Maintenance_Log__c maintenanceLog;
        public Integer score;
        public Integer overlapCount;
        public Boolean exactErrorMatch;
        public Boolean sameAsset;
        public Boolean sameModel;
        public Boolean sameManufacturer;
        public Set<String> matchedTerms;

        public ScoredRepair() {
            score = 0;
            overlapCount = 0;
            exactErrorMatch = false;
            sameAsset = false;
            sameModel = false;
            sameManufacturer = false;
            matchedTerms = new Set<String>();
        }

        public Integer compareTo(Object otherObject) {
            ScoredRepair other = (ScoredRepair) otherObject;

            if (score != other.score) {
                return score > other.score ? -1 : 1;
            }

            Date thisDate = maintenanceLog.Maintenance_Date__c;
            Date otherDate = other.maintenanceLog.Maintenance_Date__c;

            if (thisDate == otherDate) {
                return 0;
            }

            if (thisDate == null) {
                return 1;
            }

            if (otherDate == null) {
                return -1;
            }

            return thisDate > otherDate ? -1 : 1;
        }
    }

    @InvocableMethod(
        label='Get Relevant Historical Repairs'
        description='Finds and ranks successful previous repairs that may be relevant to the technician’s current Work Order. Historical repairs are evidence only and do not establish the current diagnosis.'
    )
    public static List<Result> getRelevantHistoricalRepairs(List<Request> requests) {

        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        /*
         * Agentforce normally invokes this action for one active technician
         * request at a time. Each request is nevertheless handled independently.
         */
        for (Request request : requests) {
            results.add(processRequest(request));
        }

        return results;
    }

    private static Result processRequest(Request request) {

        Result result = new Result();
        result.success = false;
        result.matchCount = 0;
        result.historicalRepairContext = '';

        if (request == null || request.workOrderId == null) {
            result.statusCode = 'INVALID_REQUEST';
            result.statusMessage = 'A current Work Order ID is required.';
            return result;
        }

        try {
            List<WorkOrder> currentWorkOrders = [
                SELECT
                    Id,
                    WorkOrderNumber,
                    Subject,
                    Description,
                    Problem_Summary__c,
                    AssetId,
                    CaseId
                FROM WorkOrder
                WHERE Id = :request.workOrderId
                WITH USER_MODE
                LIMIT 1
            ];

            if (currentWorkOrders.isEmpty()) {
                result.statusCode = 'WORK_ORDER_NOT_FOUND';
                result.statusMessage = 'The current Work Order could not be retrieved.';
                return result;
            }

            WorkOrder currentWorkOrder = currentWorkOrders[0];

            if (currentWorkOrder.AssetId == null) {
                result.statusCode = 'NO_ASSET_CONTEXT';
                result.statusMessage = 'Historical Repair Intelligence requires an Asset on the current Work Order.';
                return result;
            }                       

            List<Asset> currentAssets = [
                SELECT Id, Manufacturer__c, Model__c, Serial_Number__c, Machine_Status__c
                FROM Asset
                WHERE Id = :currentWorkOrder.AssetId
                WITH USER_MODE
                LIMIT 1
            ];

            if (currentAssets.isEmpty()) {
                result.statusCode = 'ASSET_NOT_FOUND';
                result.statusMessage = 'The Asset attached to the current Work Order could not be retrieved.';
                return result;
            }

            Asset currentAsset = currentAssets[0];

            Case currentCase;

            if (currentWorkOrder.CaseId != null) {
                List<Case> currentCases = [
                    SELECT Id, Subject, Description, Error_Code__c
                    FROM Case
                    WHERE Id = :currentWorkOrder.CaseId
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!currentCases.isEmpty()) {
                    currentCase = currentCases[0];
                }
            }

            String currentErrorCode = currentCase == null ? null : currentCase.Error_Code__c;

            String currentProblemContext = joinText(new List<String>{
                request.technicianQuery,
                currentWorkOrder.Subject,
                currentWorkOrder.Description,
                currentWorkOrder.Problem_Summary__c,
                currentCase == null ? null : currentCase.Subject,
                currentCase == null ? null : currentCase.Description,
                currentErrorCode
            });

            Set<String> currentTerms = tokenize(currentProblemContext);
            /*
            * Manufacturer and model identity are scored separately.
            * They must not also inflate textual problem similarity.
            */
            Set<String> equipmentIdentityTerms = new Set<String>();

            equipmentIdentityTerms.addAll(tokenize(currentAsset.Manufacturer__c));
            equipmentIdentityTerms.addAll(tokenize(currentAsset.Model__c));

            currentTerms.removeAll(equipmentIdentityTerms);

            if (currentTerms.isEmpty() && String.isBlank(currentErrorCode)) {
                result.statusCode = 'MISSING_PROBLEM_CONTEXT';
                result.statusMessage = 'The current Work Order does not contain enough problem or symptom information to compare with historical repairs.';
                return result;
            }

            /*
             * V1 candidate retrieval intentionally uses structured data first.
             *
             * Only confirmed successful repairs are candidate precedents:
             *   - Issue Resolved = true
             *   - Follow Up Required = false
             *   - Repair or Emergency Service
             *
             * Temporary repairs and unresolved visits are therefore never
             * presented as successful historical solutions.
             *
             * We start with the same manufacturer, then use exact model, current Asset, error code, and problem-text similarity for ranking.
             */
            List<Maintenance_Log__c> candidates;

            if (!String.isBlank(currentAsset.Manufacturer__c)) {

                candidates = [
                    SELECT
                        Id,
                        Name,
                        Asset__c,
                        Asset__r.Manufacturer__c,
                        Asset__r.Model__c,
                        Work_Order__c,
                        Work_Order__r.WorkOrderNumber,
                        Work_Order__r.Subject,
                        Work_Order__r.CaseId,
                        Maintenance_Date__c,
                        Maintenance_Type__c,
                        Summary__c,
                        Root_Cause__c,
                        Parts_Used__c,
                        Technician_Notes__c,
                        Labor_Hours__c,
                        Issue_Resolved__c,
                        Follow_Up_Required__c
                    FROM Maintenance_Log__c
                    WHERE
                        Issue_Resolved__c = TRUE
                        AND Follow_Up_Required__c = FALSE
                        AND Maintenance_Type__c IN ('Repair', 'Emergency Service')
                        AND Asset__c != NULL
                        AND Asset__r.Manufacturer__c = :currentAsset.Manufacturer__c
                        AND (Work_Order__c = NULL OR Work_Order__c != :currentWorkOrder.Id)
                    WITH USER_MODE
                    ORDER BY Maintenance_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT :CANDIDATE_LIMIT
                ];

            } else if (!String.isBlank(currentAsset.Model__c)) {

                candidates = [
                    SELECT
                        Id,
                        Name,
                        Asset__c,
                        Asset__r.Manufacturer__c,
                        Asset__r.Model__c,
                        Work_Order__c,
                        Work_Order__r.WorkOrderNumber,
                        Work_Order__r.Subject,
                        Work_Order__r.CaseId,
                        Maintenance_Date__c,
                        Maintenance_Type__c,
                        Summary__c,
                        Root_Cause__c,
                        Parts_Used__c,
                        Technician_Notes__c,
                        Labor_Hours__c,
                        Issue_Resolved__c,
                        Follow_Up_Required__c
                    FROM Maintenance_Log__c
                    WHERE
                        Issue_Resolved__c = TRUE
                        AND Follow_Up_Required__c = FALSE
                        AND Maintenance_Type__c IN ('Repair', 'Emergency Service')
                        AND Asset__c != NULL
                        AND Asset__r.Model__c = :currentAsset.Model__c
                        AND (Work_Order__c = NULL OR Work_Order__c != :currentWorkOrder.Id)
                    WITH USER_MODE
                    ORDER BY Maintenance_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT :CANDIDATE_LIMIT
                ];

            } else {
                result.statusCode = 'NO_MACHINE_CONTEXT';
                result.statusMessage = 'The current Asset does not contain a manufacturer or model for historical comparison.';
                return result;
            }

            if (candidates.isEmpty()) {
                result.statusCode = 'NO_SUCCESSFUL_HISTORY';
                result.statusMessage = 'No prior successful repair records were found for comparison.';
                return result;
            }

            /*
             * Historical Case data is retrieved separately instead of using a
             * deep relationship query. This keeps the Maintenance Log query
             * simpler and gives us exact historical error-code context.
             */
            Set<Id> historicalCaseIds = new Set<Id>();

            for (Maintenance_Log__c candidate : candidates) {
                if (candidate.Work_Order__r != null && candidate.Work_Order__r.CaseId != null) {
                    historicalCaseIds.add(candidate.Work_Order__r.CaseId);
                }
            }

            Map<Id, Case> historicalCasesById = new Map<Id, Case>();

            if (!historicalCaseIds.isEmpty()) {
                historicalCasesById = new Map<Id, Case>([
                    SELECT Id, Subject, Error_Code__c
                    FROM Case
                    WHERE Id IN :historicalCaseIds
                    WITH USER_MODE
                ]);
            }

            List<ScoredRepair> scoredRepairs = new List<ScoredRepair>();

            for (Maintenance_Log__c candidate : candidates) {

                Case historicalCase;

                if (candidate.Work_Order__r != null && candidate.Work_Order__r.CaseId != null) {
                    historicalCase = historicalCasesById.get(candidate.Work_Order__r.CaseId);
                }

                String candidateErrorCode = historicalCase == null ? null : historicalCase.Error_Code__c;

                String historicalContext = joinText(new List<String>{
                    candidate.Summary__c,
                    candidate.Root_Cause__c,
                    candidate.Parts_Used__c,
                    candidate.Technician_Notes__c,
                    candidate.Work_Order__r == null ? null : candidate.Work_Order__r.Subject, 
                    historicalCase == null ? null : historicalCase.Subject, 
                    candidateErrorCode
                });

                Set<String> historicalTerms = tokenize(historicalContext);
                historicalTerms.removeAll(equipmentIdentityTerms);

                ScoredRepair scored = new ScoredRepair();
                scored.maintenanceLog = candidate;

                scored.sameAsset = candidate.Asset__c == currentAsset.Id;

                scored.sameManufacturer =  
                    equalsIgnoreCase(candidate.Asset__r == null ? null : candidate.Asset__r.Manufacturer__c, currentAsset.Manufacturer__c);

                scored.sameModel =
                    equalsIgnoreCase(candidate.Asset__r == null ? null : candidate.Asset__r.Model__c,currentAsset.Model__c);

                scored.exactErrorMatch =
                    !String.isBlank(currentErrorCode) && !String.isBlank(candidateErrorCode) && normalize(currentErrorCode) == normalize(candidateErrorCode);

                for (String term : currentTerms) {
                    if (historicalTerms.contains(term)) {
                        scored.matchedTerms.add(term);
                    }
                }

                scored.overlapCount = scored.matchedTerms.size();

                /*
                 * Equipment relevance.
                 */
                if (scored.sameAsset) {
                    scored.score += 10;
                }

                if (scored.sameModel) {
                    scored.score += 20;
                }

                if (scored.sameManufacturer) {
                    scored.score += 8;
                }

                /*
                 * Problem relevance.
                 */
                if (scored.exactErrorMatch) {
                    scored.score += 40;
                }

                scored.score += Math.min(scored.overlapCount * 8, 48);

                /*
                 * Successful repair quality.
                 *
                 * Candidates have already been restricted to resolved,
                 * no-follow-up repairs. The repair type still adds a small
                 * preference to a normal completed Repair.
                 */
                if (candidate.Maintenance_Type__c == 'Repair') {
                    scored.score += 8;
                } else if (
                    candidate.Maintenance_Type__c == 'Emergency Service'
                ) {
                    scored.score += 5;
                }

                /*
                 * Small recency bonus. Recency should never outweigh
                 * actual problem similarity.
                 */
                if (candidate.Maintenance_Date__c != null) {
                    Integer ageDays = candidate.Maintenance_Date__c.daysBetween(Date.today());

                    if (ageDays >= 0 && ageDays <= 180) {
                        scored.score += 4;
                    } else if (ageDays > 180 && ageDays <= 365) {
                        scored.score += 2;
                    }
                }

                Boolean hasMeaningfulProblemMatch = scored.exactErrorMatch || scored.overlapCount >= 2;

                if (hasMeaningfulProblemMatch) {
                    scoredRepairs.add(scored);
                }
            }

            if (scoredRepairs.isEmpty()) {
                result.statusCode = 'NO_RELEVANT_HISTORY';
                result.statusMessage =
                    'Successful historical repairs exist, but none were relevant enough to the current problem to present as repair precedents.';
                return result;
            }

            scoredRepairs.sort();

            Integer requestedMax = request.maxResults == null ? DEFAULT_MAX_RESULTS  : request.maxResults;

            if (requestedMax < 1) {
                requestedMax = DEFAULT_MAX_RESULTS;
            }

            requestedMax = Math.min(requestedMax, MAX_RESULTS_ALLOWED);

            Integer resultCount = Math.min(requestedMax, scoredRepairs.size());

            String context = buildHistoricalRepairContext(currentWorkOrder, currentAsset, currentErrorCode, scoredRepairs, resultCount);

            result.success = true;
            result.statusCode = 'SUCCESS';
            result.matchCount = resultCount;
            result.statusMessage = 'Relevant successful historical repairs were found.';
            result.historicalRepairContext = context;

            return result;

        } catch (Exception e) {

            result.success = false;
            result.statusCode = 'SYSTEM_ERROR';
            result.statusMessage = 'Historical Repair Intelligence could not retrieve repair history.';
            result.matchCount = 0;
            result.historicalRepairContext = '';

            return result;
        }
    }

    private static String buildHistoricalRepairContext(
        WorkOrder currentWorkOrder,
        Asset currentAsset,
        String currentErrorCode,
        List<ScoredRepair> scoredRepairs,
        Integer resultCount
    ) {
        List<String> lines = new List<String>();

        lines.add('HISTORICAL REPAIR INTELLIGENCE');
        lines.add('');
        lines.add('Current machine: ' + safe(currentAsset.Manufacturer__c) + ' ' + safe(currentAsset.Model__c));

        if (!String.isBlank(currentWorkOrder.WorkOrderNumber)) {
            lines.add( 'Current Work Order: ' + currentWorkOrder.WorkOrderNumber);
        }

        if (!String.isBlank(currentErrorCode)) {
            lines.add('Current error code: ' + currentErrorCode);
        }

        lines.add('');
        lines.add('Relevant successful repair precedents:');

        for (Integer i = 0; i < resultCount; i++) {

            ScoredRepair scored = scoredRepairs[i];
            Maintenance_Log__c logRecord = scored.maintenanceLog;

            lines.add('');
            lines.add(String.valueOf(i + 1) + '. ' + logRecord.Name);

            if (logRecord.Maintenance_Date__c != null) {
                lines.add('Date: ' + String.valueOf(logRecord.Maintenance_Date__c));
            }

            if (logRecord.Asset__r != null) {
                lines.add('Machine: ' +  safe(logRecord.Asset__r.Manufacturer__c) + ' ' + safe(logRecord.Asset__r.Model__c));
            }

            if (logRecord.Work_Order__r != null && !String.isBlank(logRecord.Work_Order__r.WorkOrderNumber)) {
                lines.add('Historical Work Order: ' + logRecord.Work_Order__r.WorkOrderNumber);
            }

            List<String> basis = new List<String>();

            if (scored.exactErrorMatch) {
                basis.add('same error code');
            }

            if (scored.sameAsset) {
                basis.add('same Asset');
            }

            if (scored.sameModel) {
                basis.add('same model');
            } else if (scored.sameManufacturer) {
                basis.add('same manufacturer');
            }

            if (!scored.matchedTerms.isEmpty()) {
                List<String> matchedTerms = new List<String>(scored.matchedTerms);

                Integer termsToShow = Math.min(5, matchedTerms.size());

                List<String> displayedTerms = new List<String>();

                for (Integer j = 0; j < termsToShow; j++) {
                    displayedTerms.add(matchedTerms[j]);
                }

                basis.add('matching problem terms: ' + String.join(displayedTerms, ', '));
            }

            if (!basis.isEmpty()) {
                lines.add('Why relevant: ' + String.join(basis, '; '));
            }

            if (!String.isBlank(logRecord.Summary__c)) {
                lines.add('Successful repair: ' + clip(logRecord.Summary__c, 600));
            }

            if (!String.isBlank(logRecord.Root_Cause__c)) {
                lines.add('Recorded root cause: ' + clip(logRecord.Root_Cause__c, 500));
            }

            if (!String.isBlank(logRecord.Parts_Used__c)) {
                lines.add('Parts used: ' + clip(logRecord.Parts_Used__c, 400));
            }

            if (logRecord.Labor_Hours__c != null) {
                lines.add('Labor hours: ' +  String.valueOf(logRecord.Labor_Hours__c));
            }

            lines.add('Outcome: Issue resolved; no follow-up required.');
        }

        lines.add('');
        lines.add(
            'IMPORTANT: Historical repair precedents are supporting evidence only. ' +
            'They do not prove that the current machine has the same root cause. ' +
            'Verify the current machine condition and use approved MillTrack service documentation before performing a repair or ordering parts.'
        );

        return String.join(lines, '\n');
    }

    private static Set<String> tokenize(String value) {

        Set<String> terms = new Set<String>();

        String normalizedValue = normalize(value);

        if (String.isBlank(normalizedValue)) {
            return terms;
        }

        for (String term : normalizedValue.split('\\s+')) {

            if (String.isBlank(term) || term.length() < 3 || STOP_WORDS.contains(term)) {
                continue;
            }

            terms.add(term);
        }

        return terms;
    }

    private static String normalize(String value) {

        if (String.isBlank(value)) {
            return '';
        }

        return value.toLowerCase().replaceAll('[^a-z0-9]+', ' ').trim();
    }

    private static Boolean equalsIgnoreCase(String leftValue, String rightValue) {
        if (String.isBlank(leftValue) || String.isBlank(rightValue)) {
            return false;
        }

        return leftValue.trim().toLowerCase() == rightValue.trim().toLowerCase();
    }

    private static String joinText(List<String> values) {

        List<String> populated = new List<String>();

        for (String value : values) {
            if (!String.isBlank(value)) {
                populated.add(value);
            }
        }

        return String.join(populated, ' ');
    }

    private static String clip(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return '';
        }

        String trimmed = value.trim();

        if (trimmed.length() <= maxLength) {
            return trimmed;
        }

        return trimmed.substring(0, maxLength) + '…';
    }

    private static String safe(String value) {
        return String.isBlank(value) ? 'Not available' : value.trim();
    }
}